// SPDX-License-Identifier: PRIVATE
pragma solidity >=0.7.0 <0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./data.sol";

contract CrossLend is IERC777Recipient, ReentrancyGuard{
  //////////////////// for using
  using ChainQueueLib for ChainManager;
  using SafeMath for uint256;

  //////////////////// constant
  IERC1820Registry constant internal _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

  bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

  uint256 constant Decimal = 1e18;

  uint256 public OneDayTime;

  //////////////////// var
  SystemInfo internal SInfo;
  
  IERC777 public CRFI;
  IERC777 public CFil;
  IERC777 public SFil;

  //////////////////// modifier
  modifier IsAdmin() {
    require(msg.sender == SInfo.SuperAdmin || SInfo.Admins[msg.sender], "only admin");
    _;
  }

  modifier IsSuperAdmin() {
    require(SInfo.SuperAdmin == msg.sender, "only super admin");
    _;
  }

  //////////////////// event
  event AffEvent(address indexed receiver, address indexed sender, uint256 indexed affTimes, uint256 crfiInterest, uint256 cfilInterest, uint256 packageID, uint256 timestamp);

  event AffBought(address indexed affer, address indexed sender, uint256 indexed affPackageTimes, uint256 amount, uint256 packageID, uint256 timestamp);
  
  event loanCFilEvent(address indexed addr, uint256 cfilAmount, uint256 sfilAmount);

  //////////////////// constructor
  constructor(address crfiAddr, address cfilAddr, address sfilAddr) {
    CRFI = IERC777(crfiAddr);
    CFil = IERC777(cfilAddr);
    SFil = IERC777(sfilAddr);
    OneDayTime = 60 * 60 * 24;

    SInfo.SuperAdmin = msg.sender;

    SInfo.AffRate = Decimal / 10;
    SInfo.EnableAffCFil = 1;

    SInfo.ChainM.InitChainManager();
    
    ////////// add package

    SInfo.crfiMinerPerDayCFil = 1917808 * Decimal / 100;
    SInfo.crfiMinerPerDayCRFI = 821918 * Decimal / 100;

    SInfo.ParamUpdateTime = block.timestamp;
    
    // loan CFil
    ChangeLoanRate(201 * Decimal / 1000,
                   56 * Decimal / 100,
                   2300 * Decimal);
    SInfo.LoanCFil.UpdateTime = block.timestamp;

    // add crfi
    AddPackage(FinancialType.CRFI,
               0,
               (20 * Decimal) / 1000,
               Decimal);
    
    AddPackage(FinancialType.CRFI,
               90,
               (32 * Decimal) / 1000,
               (15 * Decimal) / 10);

    AddPackage(FinancialType.CRFI,
               180,
               (34 * Decimal) / 1000,
               2 * Decimal);

    AddPackage(FinancialType.CRFI,
               365,
               (36 * Decimal) / 1000,
               (25 * Decimal) / 10);
                   
    AddPackage(FinancialType.CRFI,
               540,
               (40 * Decimal) / 1000,
               3 * Decimal);
    
    // add cfil
    AddPackage(FinancialType.CFil,
               0,
               (20 * Decimal) / 1000,
               Decimal);
    
    AddPackage(FinancialType.CFil,
               90,
               (33 * Decimal) / 1000,
               (15 * Decimal) / 10);

    AddPackage(FinancialType.CFil,
               180, 
               (35 * Decimal) / 1000,
               2 * Decimal);

    AddPackage(FinancialType.CFil,
               365,
               (37 * Decimal) / 1000,
               (25 * Decimal) / 10);
                   
    AddPackage(FinancialType.CFil,
               540,
               (41 * Decimal) / 1000,
               3 * Decimal);
    
    // register interfaces
    _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
  }
  
  //////////////////// super admin func
  function AddAdmin(address admin)
    public
    IsSuperAdmin(){
    require(!SInfo.Admins[admin], "already add this admin");
    SInfo.Admins[admin] = true;
  }

  function DelAdmin(address admin)
    public
    IsSuperAdmin(){
    require(SInfo.Admins[admin], "this addr is not admin");
    SInfo.Admins[admin] = false;
  }

  function ChangeSuperAdmin(address suAdmin)
    public
    IsSuperAdmin(){
    require(suAdmin != address(0x0), "empty new super admin");

    if(suAdmin == SInfo.SuperAdmin){
      return;
    }
    
    SInfo.SuperAdmin = suAdmin;
  }

  //////////////////// admin func
  function SetMap(string memory key,
                  string memory value)
    public
    IsAdmin(){

    SInfo.kvMap[key] = value;
  }
  
  function ChangePackageRate(uint256 packageID,
                             uint256 cfilInterestRate,
                             uint256 weight)
    public
    IsAdmin(){
    
    require(packageID < SInfo.Packages.length, "packageID error");

    updateAllParam();
    
    FinancialPackage storage package = SInfo.Packages[packageID];
    package.CFilInterestRate = cfilInterestRate;

    uint256 nowTotal = package.Total.mul(package.Weight) / Decimal;
    if(package.Type == FinancialType.CRFI){
      SInfo.totalWeightCRFI = SInfo.totalWeightCRFI.sub(nowTotal);
    } else {
      SInfo.totalWeightCFil = SInfo.totalWeightCFil.sub(nowTotal);
    }

    package.Weight = weight;

    nowTotal = package.Total.mul(package.Weight) / Decimal;
    if(package.Type == FinancialType.CRFI){
      SInfo.totalWeightCRFI = SInfo.totalWeightCRFI.add(nowTotal);
    } else {
      SInfo.totalWeightCFil = SInfo.totalWeightCFil.add(nowTotal);
    }
  }

  function AddPackage(FinancialType _type,
                      uint256 dayTimes,
                      uint256 cfilInterestRate,
                      uint256 weight)
    public
    IsAdmin(){

    updateAllParam();
    
    uint256 idx = SInfo.Packages.length;
    SInfo.Packages.push();
    FinancialPackage storage package = SInfo.Packages[idx];

    package.Type = _type;
    package.Days = dayTimes;
    package.Weight = weight;
    package.CFilInterestRate = cfilInterestRate;
    package.ID = idx;
  }

  function ChangeCRFIMinerPerDay(uint256 crfi, uint256 cfil)
    public
    IsAdmin(){

    updateAllParam();

    SInfo.crfiMinerPerDayCFil = cfil;
    SInfo.crfiMinerPerDayCRFI = crfi;
  }

  function ChangeLoanRate(uint256 apy, uint256 pledgeRate, uint256 paymentDue)
    public
    IsAdmin(){

    require(pledgeRate > 0, "pledge rate can't = 0");

    SInfo.LoanCFil.APY = apy;
    SInfo.LoanCFil.PledgeRate = pledgeRate;
    SInfo.LoanCFil.PaymentDue = paymentDue;
    SInfo.LoanCFil.PaymentDue99 = paymentDue.mul(99) / 100;
  }

  function ChangeAffCFil(bool enable)
    public
    IsAdmin(){
    if(enable && SInfo.EnableAffCFil == 0){
      SInfo.EnableAffCFil = 1;
    } else if(!enable && SInfo.EnableAffCFil > 0){
      SInfo.EnableAffCFil = 0;
    }
  }

  function ChangeAffRate(uint256 rate)
    public
    IsAdmin(){
    
    SInfo.AffRate = rate;
  }

  function ChangeAffRequire(uint256 amount)
    public
    IsAdmin(){
    SInfo.AffRequire = amount;
  }

  function WithdrawCRFIInterestPool(uint256 amount)
    public
    IsAdmin(){
    SInfo.crfiInterestPool = SInfo.crfiInterestPool.sub(amount);
    CRFI.send(msg.sender, amount, "");
  }

  function WithdrawCFilInterestPool(uint256 amount)
    public
    IsAdmin(){
    SInfo.cfilInterestPool = SInfo.cfilInterestPool.sub(amount);
    CFil.send(msg.sender, amount, "");
  }
  
  //////////////////// public
  function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData)
    public
    override
    nonReentrant(){

    ////////// check
    require(userData.length > 0, "no user data");
    
    // mode = 0, normal bought financial package
    // mode = 2, charge cfil interest pool
    // mode = 3, charge crfi interest pool
    // mode = 4, loan cfil
    // mode = 5, repay cfil by loan
    (uint256 mode, uint256 param, address addr) = abi.decode(userData, (uint256,uint256, address));
    require(from != address(0x0), "from is zero");

    if(mode == 5){
      _repayLoanCFil(from, amount);
    }else if(mode == 4){
      _loanCFil(from, amount);
    }else if(mode == 3){
      require(amount > 0, "no amount");
      require(msg.sender == address(CRFI), "only charge crfi");
      SInfo.crfiInterestPool = SInfo.crfiInterestPool.add(amount);
      return;
    }else if(mode == 2){
      require(amount > 0, "no amount");
      require(msg.sender == address(CFil), "only charge cfil");
      SInfo.cfilInterestPool = SInfo.cfilInterestPool.add(amount);
      
      return;
    } else if (mode == 0){
      _buyFinancialPackage(from, param, addr, amount);
    } else {
      revert("mode error");
    }
  }
  
  function Withdraw(uint256 packageID, bool only, uint256 maxNum)
    public
    nonReentrant(){

    InvestInfo storage uInfo = SInfo.Invests[getUID(msg.sender)];
    
    uint256 cfil;
    uint256 cfilInterest;
    uint256 crfi;
    uint256 crfiInterest;

    (crfi, crfiInterest, cfil, cfilInterest) = _withdrawFinancial(uInfo, packageID, only, maxNum);

    if(crfi > 0){
      uInfo.nowInvestFinCRFI = uInfo.nowInvestFinCRFI.sub(crfi);
    }
    if(cfil > 0){
      uInfo.nowInvestFinCFil = uInfo.nowInvestFinCFil.sub(cfil);
    }

    withdrawCoin(uInfo.Addr, crfi, crfiInterest, cfil, cfilInterest);
  }

  //////////////////// view func

  function GetMap(string memory key)
    public
    view
    returns(string memory value){

    return SInfo.kvMap[key];
  }

  function GetFinancialPackage()
    public
    view
    returns(FinancialPackage[] memory packages){

    packages = new FinancialPackage[](SInfo.Packages.length);
    for(uint256 packageID = 0; packageID < SInfo.Packages.length; packageID++){
      packages[packageID] = SInfo.Packages[packageID];
      packages[packageID].CRFIInterestRateDyn = getFinancialCRFIRate(SInfo.Packages[packageID]);
    }
    
    return packages;
  }

  function GetInvesterFinRecords(address addr)
    public
    view
    returns(QueueData[] memory records){

    uint256 uid = SInfo.InvestAddrID[addr];
    if(uid == 0){
      return records;
    }

    InvestInfo storage uInfo = SInfo.Invests[uid];

    uint256 recordSize = 0;

    for(uint256 packageID = 0; packageID < SInfo.Packages.length; packageID++){
      ChainQueue storage chain = uInfo.InvestRecords[packageID];
      recordSize = recordSize.add(chain.Size);
    }

    records = new QueueData[](recordSize);
    uint256 id = 0;
    
    for(uint256 packageID = 0; packageID < SInfo.Packages.length; packageID++){
      ChainQueue storage chain = uInfo.InvestRecords[packageID];
      if(chain.Size == 0){
        continue;
      }

      ChainItem storage item = SInfo.ChainM.GetFirstItem(chain);
      for(;;){
        records[id] = item.Data;
        id++;

        if(!SInfo.ChainM.HasNext(item)){
          break;
        }

        item = SInfo.ChainM.Next(item);
      }
    }
    
    return records;
  }


  function GetSystemInfo()
    public
    view
    returns(SystemInfoView memory sInfoView){

    sInfoView.AffRate = SInfo.AffRate;
    sInfoView.AffRequire = SInfo.AffRequire;
    sInfoView.EnableAffCFil = SInfo.EnableAffCFil;
    sInfoView.NewInvestID = SInfo.NewInvestID;
    sInfoView.nowInvestCRFI = SInfo.nowInvestCRFI;
    sInfoView.nowInvestCFil = SInfo.nowInvestCFil;
    sInfoView.cfilInterestPool = SInfo.cfilInterestPool;
    sInfoView.crfiInterestPool = SInfo.crfiInterestPool;

    sInfoView.cfilLendingTotal = SInfo.cfilLendingTotal;
    sInfoView.crfiRewardTotal = SInfo.crfiRewardTotal;
    sInfoView.avaiCFilAmount = SInfo.avaiCFilAmount;
  
    sInfoView.totalWeightCFil = SInfo.totalWeightCFil;
    sInfoView.totalWeightCRFI = SInfo.totalWeightCRFI;
    sInfoView.crfiMinerPerDayCFil = SInfo.crfiMinerPerDayCFil;
    sInfoView.crfiMinerPerDayCRFI = SInfo.crfiMinerPerDayCRFI;
  
    sInfoView.ParamUpdateTime = SInfo.ParamUpdateTime;

    return sInfoView;
  }

  function GetPackages()
    public
    view
    returns(FinancialPackage[] memory financialPackages,
            LoanCFilPackage memory loanCFil){

    return (GetFinancialPackage(),
            SInfo.LoanCFil);
  }


  function GetInvestRecords(address addr)
    public
    view
    returns(QueueData[] memory records,
            LoanInvest memory loanInvest,
            InterestDetail[] memory interestDetail){

    uint256 uid = SInfo.InvestAddrID[addr];
    if(uid == 0){
      return (records, loanInvest, interestDetail);
    }

    InvestInfo storage uInfo = SInfo.Invests[uid];

    records = GetInvesterFinRecords(addr);
    interestDetail = new InterestDetail[](records.length+1);

    uint256 id = 0;
    for(; id < records.length; id++){
      (interestDetail[id].crfiInterest, interestDetail[id].cfilInterest) = _calcInvestFinancial(records[id].PackageID, records[id].Amount, records[id].ParamCRFI, records[id].ParamCFil);
    }

    interestDetail[id].cfilInterest = calcInvestLoanStatus(uInfo);
    interestDetail[id].cfilInterest = interestDetail[id].cfilInterest.add(uInfo.LoanCFil.NowInterest);

    return(records,
           uInfo.LoanCFil,
           interestDetail);
  }

  function GetInvestInfo(uint256 uid, address addr)
    public
    view
    returns(bool admin,
            InvestInfoView memory uInfoView){
    if(uid == 0){
      uid = SInfo.InvestAddrID[addr];
    }

    if(uid == 0){
      if(addr != address(0x0)){
        admin = (SInfo.SuperAdmin == addr) || (SInfo.Admins[addr]);
      }
      return (admin,
              uInfoView);
    }
    
    InvestInfo storage uInfo = SInfo.Invests[uid];

    admin = (SInfo.SuperAdmin == uInfo.Addr) || (SInfo.Admins[uInfo.Addr]);

    uInfoView.Addr = uInfo.Addr;
    uInfoView.ID = uInfo.ID;
    uInfoView.affID = uInfo.affID;
    uInfoView.totalAffTimes = uInfo.totalAffTimes;
    uInfoView.totalAffPackageTimes = uInfo.totalAffPackageTimes;
    uInfoView.totalAffCRFI = uInfo.totalAffCRFI;
    uInfoView.totalAffCFil = uInfo.totalAffCFil;
    uInfoView.nowInvestFinCRFI = uInfo.nowInvestFinCRFI;
    uInfoView.nowInvestFinCFil = uInfo.nowInvestFinCFil;

    return (admin,
            uInfoView);
  }

  function calcSFilToCFil(uint256 sfil)
    public
    view
    returns(uint256 cfil){
    cfil = sfil.mul(SInfo.LoanCFil.PledgeRate) / Decimal;
    return cfil;
  }

  function calcCFilToSFil(uint256 cfil)
    public
    view
    returns(uint256 sfil){

    sfil = cfil.mul(Decimal) / SInfo.LoanCFil.PledgeRate;
    return sfil;
  }
  
  //////////////////// for debug

  function getChainMDetail()
    public
    view
    returns(ChainManager memory chaimM){

    return SInfo.ChainM;
  }

  function getInvestChainDetail(uint256 id)
    public
    view
    returns(ChainQueue[] memory chains){

    InvestInfo storage uInfo = SInfo.Invests[id];

    chains = new ChainQueue[](SInfo.Packages.length);

    for(uint256 packageID = 0; packageID < SInfo.Packages.length; packageID++){
      chains[packageID] = uInfo.InvestRecords[packageID];
    }

    return chains;
  }
  
  //////////////////// internal func
  function _repayLoanCFil(address from,
                          uint256 cfilAmount)
    internal{
    require(cfilAmount > 0, "no cfil amount");
    require(msg.sender == address(CFil), "not cfil coin type");

    InvestInfo storage uInfo = SInfo.Invests[getUID(from)];
    updateInvesterLoanCFil(uInfo);

    // deal interest
    uint256 repayInterest = cfilAmount;
    if(uInfo.LoanCFil.NowInterest < cfilAmount){
      repayInterest = uInfo.LoanCFil.NowInterest;
    }

    uInfo.LoanCFil.NowInterest = uInfo.LoanCFil.NowInterest.sub(repayInterest);
    SInfo.cfilInterestPool = SInfo.cfilInterestPool.add(repayInterest);
    cfilAmount = cfilAmount.sub(repayInterest);

    // deal lending
    if(cfilAmount == 0){
      return;
    }

    uint256 repayLending = cfilAmount;
    if(uInfo.LoanCFil.Lending < cfilAmount){
      repayLending = uInfo.LoanCFil.Lending;
    }

    uint256 pledge = repayLending.mul(uInfo.LoanCFil.Pledge) / uInfo.LoanCFil.Lending;
    uInfo.LoanCFil.Lending = uInfo.LoanCFil.Lending.sub(repayLending);
    uInfo.LoanCFil.Pledge = uInfo.LoanCFil.Pledge.sub(pledge);
    SInfo.cfilLendingTotal = SInfo.cfilLendingTotal.sub(repayLending);
    SInfo.avaiCFilAmount = SInfo.avaiCFilAmount.add(repayLending);
    cfilAmount = cfilAmount.sub(repayLending);

    if(pledge > 0){
      SFil.send(from, pledge, "");
    }
    
    if(cfilAmount > 0){
      CFil.send(from, cfilAmount, "");
    }
  }
  
  function _loanCFil(address from,
                     uint256 sfilAmount)
    internal{

    require(sfilAmount > 0, "no sfil amount");
    require(msg.sender == address(SFil), "not sfil coin type");

    uint256 cfilAmount = calcSFilToCFil(sfilAmount);
    require(cfilAmount <= SInfo.avaiCFilAmount, "not enough cfil to loan");
    require(cfilAmount >= SInfo.LoanCFil.PaymentDue99, "cfil amount is too small");

    InvestInfo storage uInfo = SInfo.Invests[getUID(from)];
    updateInvesterLoanCFil(uInfo);
    
    if(uInfo.LoanCFil.Param < SInfo.LoanCFil.Param){
      uInfo.LoanCFil.Param = SInfo.LoanCFil.Param;
    }
    uInfo.LoanCFil.Lending = uInfo.LoanCFil.Lending.add(cfilAmount);
    uInfo.LoanCFil.Pledge = uInfo.LoanCFil.Pledge.add(sfilAmount);

    SInfo.cfilLendingTotal = SInfo.cfilLendingTotal.add(cfilAmount);
    SInfo.avaiCFilAmount = SInfo.avaiCFilAmount.sub(cfilAmount);

    CFil.send(from, cfilAmount, "");
    emit loanCFilEvent(from, cfilAmount, sfilAmount);
  }
  
  function _buyFinancialPackage(address from,
                                uint256 packageID,
                                address affAddr,
                                uint256 amount)
    internal{
    // check
    require(amount > 0, "no amount");
    require(packageID < SInfo.Packages.length, "invalid packageID");
    FinancialPackage storage package = SInfo.Packages[packageID];
    if(package.Type == FinancialType.CRFI){
      require(msg.sender == address(CRFI), "not CRFI coin type");
    }else if(package.Type == FinancialType.CFil){
      require(msg.sender == address(CFil), "not CFil coin type");
    } else {
      revert("not avai package type");
    }

    updateAllParam();
    
    // exec
    InvestInfo storage uInfo = SInfo.Invests[getUID(from)];    

    uint256 affID = uInfo.affID;

    if(affID == 0 && affAddr != from && affAddr != address(0x0)){
      uInfo.affID = getUID(affAddr);
      affID = uInfo.affID;
    }

    if(package.Days == 0){
      affID = 0;
    }

    if(affID != 0){
      InvestInfo storage affInfo = SInfo.Invests[affID];
      affInfo.totalAffPackageTimes++;      
      emit AffBought(affAddr, from, affInfo.totalAffPackageTimes, amount, packageID, block.timestamp); 
    }

    ChainQueue storage recordQ = uInfo.InvestRecords[package.ID];

    ChainItem storage item = SInfo.ChainM.GetAvaiItem();

    item.Data.Type = package.Type;
    item.Data.PackageID = package.ID;
    item.Data.Days = package.Days;
    item.Data.EndTime = block.timestamp.add(package.Days.mul(OneDayTime));
    item.Data.AffID = affID;
    item.Data.Amount = amount;
    item.Data.ParamCRFI = package.ParamCRFI;
    item.Data.ParamCFil = package.ParamCFil;

    SInfo.ChainM.PushEndItem(recordQ, item);

    ////////// for statistic
    package.Total = package.Total.add(amount);
    if(package.Type == FinancialType.CRFI){
      uInfo.nowInvestFinCRFI = uInfo.nowInvestFinCRFI.add(amount);
      SInfo.nowInvestCRFI = SInfo.nowInvestCRFI.add(amount);
      SInfo.totalWeightCRFI = SInfo.totalWeightCRFI.add(amount.mul(package.Weight) / Decimal);
    } else if(package.Type == FinancialType.CFil){
      uInfo.nowInvestFinCFil = uInfo.nowInvestFinCFil.add(amount);
      SInfo.nowInvestCFil = SInfo.nowInvestCFil.add(amount);
      SInfo.avaiCFilAmount = SInfo.avaiCFilAmount.add(amount);
      SInfo.totalWeightCFil = SInfo.totalWeightCFil.add(amount.mul(package.Weight) / Decimal);
    }
  }

  function _withdrawFinancial(InvestInfo storage uInfo, uint256 onlyPackageID, bool only, uint256 maxNum)
    internal
    returns(uint256 crfi,
            uint256 crfiInterest,
            uint256 cfil,
            uint256 cfilInterest){

    updateAllParam();

    if(!only){
      onlyPackageID = 0;
    }

    if(maxNum == 0){
      maxNum -= 1;
    }
    
    (uint256 packageID, ChainItem storage item, bool has) = getFirstValidItem(uInfo, onlyPackageID);
    
    while(has && maxNum > 0 && (!only || packageID == onlyPackageID)){
      maxNum--;
      QueueData storage data = item.Data;
      FinancialPackage storage package = SInfo.Packages[data.PackageID];

      (uint256 _crfiInterest, uint256 _cfilInterest) = calcInvestFinancial(data);
      crfiInterest = crfiInterest.add(_crfiInterest);
      cfilInterest = cfilInterest.add(_cfilInterest);

      addAffCRFI(uInfo, data, _crfiInterest, _cfilInterest);

      if((block.timestamp > data.EndTime && data.Days > 0) || (data.Days ==0 && only)){
        package.Total = package.Total.sub(data.Amount);
        if(data.Type == FinancialType.CFil){
          cfil = cfil.add(data.Amount);
          SInfo.totalWeightCFil = SInfo.totalWeightCFil.sub(data.Amount.mul(package.Weight) / Decimal);
        } else {
          crfi = crfi.add(data.Amount);
          SInfo.totalWeightCRFI = SInfo.totalWeightCRFI.sub(data.Amount.mul(package.Weight) / Decimal);
        }
        SInfo.ChainM.PopPutFirst(uInfo.InvestRecords[packageID]);
        (packageID, item, has) = getFirstValidItem(uInfo, packageID);
      } else {
        data.ParamCRFI = package.ParamCRFI;
        data.ParamCFil = package.ParamCFil;
        (packageID, item, has) = getNextItem(uInfo, packageID, item);
      }
    }

    return (crfi, crfiInterest, cfil, cfilInterest);
  }
        
  function getUID(address addr) internal returns(uint256 uID){
    uID = SInfo.InvestAddrID[addr];
    if(uID != 0){
      return uID;
    }
    
    SInfo.NewInvestID++;
    uID = SInfo.NewInvestID;

    InvestInfo storage uInfo = SInfo.Invests[uID];
    uInfo.Addr = addr;
    uInfo.ID = uID;
        
    SInfo.InvestAddrID[addr] = uID;
    return uID;
  }

  function calcSystemLoanStatus()
    internal
    view
    returns(uint256 param){

    if(block.timestamp == SInfo.LoanCFil.UpdateTime){
      return SInfo.LoanCFil.Param;
    }

    uint256 diffSec = block.timestamp.sub(SInfo.LoanCFil.UpdateTime);

    param = SInfo.LoanCFil.Param.add(calcInterest(Decimal, SInfo.LoanCFil.APY, diffSec));

    return param;
  }

  function calcInvestLoanStatus(InvestInfo storage uInfo)
    internal
    view
    returns(uint256 cfilInterest){

    if(uInfo.LoanCFil.Lending == 0){
      return 0;
    }
    
    uint256 param = calcSystemLoanStatus();
    if(uInfo.LoanCFil.Param >= param){
      return 0;
    }
    
    cfilInterest = uInfo.LoanCFil.Lending.mul(param.sub(uInfo.LoanCFil.Param)) / Decimal;
    
    return cfilInterest;
  }

  function updateSystemLoanStatus()
    internal{
    uint256 param;
    param = calcSystemLoanStatus();
    if(param <= SInfo.LoanCFil.Param){
      return;
    }

    SInfo.LoanCFil.Param = param;
    SInfo.LoanCFil.UpdateTime = block.timestamp;
  }

  function updateInvesterLoanCFil(InvestInfo storage uInfo)
    internal{
    updateSystemLoanStatus();
    uint256 cfilInterest = calcInvestLoanStatus(uInfo);
    if(cfilInterest == 0){
      return;
    }

    uInfo.LoanCFil.Param = SInfo.LoanCFil.Param;
    uInfo.LoanCFil.NowInterest = uInfo.LoanCFil.NowInterest.add(cfilInterest);
  }

  function calcInterest(uint256 amount, uint256 rate, uint256 sec)
    internal
    view
    returns(uint256){
    
    return amount.mul(rate).mul(sec) / 365 / OneDayTime / Decimal;    
  }

  function getFirstValidItem(InvestInfo storage uInfo, uint256 packageID)
    internal
    view
    returns(uint256 newPackageID, ChainItem storage item, bool has){
    
    while(packageID < SInfo.Packages.length){
      ChainQueue storage chain = uInfo.InvestRecords[packageID];
      if(chain.Size == 0){
        packageID++;
        continue;
      }
      item = SInfo.ChainM.GetFirstItem(chain);
      return (packageID, item, true);
    }

    return (0, SInfo.ChainM.GetNullItem(), false);
  }

  function getNextItem(InvestInfo storage uInfo,
                       uint256 packageID,
                       ChainItem storage item)
    internal
    view
    returns(uint256, ChainItem storage, bool){

    if(packageID >= SInfo.Packages.length){
      return (0, item, false);
    }

    if(SInfo.ChainM.HasNext(item)){
      return (packageID, SInfo.ChainM.Next(item), true);
    }

    return getFirstValidItem(uInfo, packageID+1);
  }

  function addAffCRFI(InvestInfo storage uInfo, QueueData storage data, uint256 crfiInterest, uint256 cfilInterest)
    internal{
    if(data.Days == 0){
      return;
    }
    
    uint256 affID = data.AffID;
    if(affID == 0){
      return;
    }
    InvestInfo storage affInfo = SInfo.Invests[affID];
    if(affInfo.nowInvestFinCFil < SInfo.AffRequire){
      return;
    }
    
    uint256 affCRFI = crfiInterest.mul(SInfo.AffRate) / Decimal;
    uint256 affCFil;

    bool emitFlag;
    if(affCRFI != 0){
      emitFlag = true;
      affInfo.totalAffCRFI = affInfo.totalAffCRFI.add(affCRFI);
    }

    if(SInfo.EnableAffCFil > 0){
      affCFil = cfilInterest.mul(SInfo.AffRate) / Decimal;
      if(affCFil != 0){
        emitFlag = true;
        affInfo.totalAffCFil = affInfo.totalAffCFil.add(affCFil);
      }
    }

    if(!emitFlag){
      return;
    }
    
    affInfo.totalAffTimes++;
    emit AffEvent(affInfo.Addr, uInfo.Addr, affInfo.totalAffTimes, affCRFI, affCFil, data.PackageID, block.timestamp);

    withdrawCoin(affInfo.Addr, 0, affCRFI, 0, affCFil);

  }

  function withdrawCoin(address addr,
                        uint256 crfi,
                        uint256 crfiInterest,
                        uint256 cfil,
                        uint256 cfilInterest)
    internal{
    
    require(cfil <= SInfo.nowInvestCFil, "cfil invest now error");
    require(cfil <= SInfo.avaiCFilAmount, "not enough cfil to withdraw");    
    require(crfi <= SInfo.nowInvestCRFI, "crfi invest now error");
    
    if(cfil > 0){
      SInfo.nowInvestCFil = SInfo.nowInvestCFil.sub(cfil);
      SInfo.avaiCFilAmount = SInfo.avaiCFilAmount.sub(cfil);
    }

    if(crfi > 0){
      SInfo.nowInvestCRFI = SInfo.nowInvestCRFI.sub(crfi);
    }
    
    if(cfilInterest > 0){
      require(SInfo.cfilInterestPool >= cfilInterest, "cfil interest pool is not enough");
      SInfo.cfilInterestPool = SInfo.cfilInterestPool.sub(cfilInterest);
      cfil = cfil.add(cfilInterest);
    }

    if(crfiInterest > 0){
      require(SInfo.crfiInterestPool >= crfiInterest, "crfi interest pool is not enough");
      SInfo.crfiInterestPool = SInfo.crfiInterestPool.sub(crfiInterest);
      crfi = crfi.add(crfiInterest);
      SInfo.crfiRewardTotal = SInfo.crfiRewardTotal.add(crfiInterest);
    }

    if(cfil > 0){
      CFil.send(addr, cfil, "");
    }

    if(crfi > 0){
      CRFI.send(addr, crfi, "");
    }
  }

  //////////////////// for update param
  
  function getFinancialCRFIRate(FinancialPackage storage package)
    internal
    view
    returns(uint256 rate){
    if(package.Total == 0){
      return 0;
    }
    
    uint256 x = package.Total.mul(package.Weight);
    if(package.Type == FinancialType.CRFI){
      if(SInfo.totalWeightCRFI == 0){
        return 0;
      }
      rate = x.mul(SInfo.crfiMinerPerDayCRFI) / SInfo.totalWeightCRFI;
    } else {
      if(SInfo.totalWeightCFil == 0){
        return 0;
      }
      rate = x.mul(SInfo.crfiMinerPerDayCFil) / SInfo.totalWeightCFil;
    }

    rate = rate.mul(365) / package.Total ;
    
    return rate;
  }

  function calcFinancialParam(FinancialPackage storage package)
    internal
    view
    returns(uint256 paramCRFI,
            uint256 paramCFil){

    uint256 diffSec = block.timestamp.sub(SInfo.ParamUpdateTime);
    if(diffSec == 0){
      return (package.ParamCRFI, package.ParamCFil);
    }

    paramCFil = package.ParamCFil.add(calcInterest(Decimal, package.CFilInterestRate, diffSec));
    paramCRFI = package.ParamCRFI.add(calcInterest(Decimal,
                                                   getFinancialCRFIRate(package),
                                                   diffSec));
    return (paramCRFI, paramCFil);
  }

  function updateFinancialParam(FinancialPackage storage package)
    internal{

    (package.ParamCRFI, package.ParamCFil) = calcFinancialParam(package);
  }

  function updateAllParam()
    internal{
    if(block.timestamp == SInfo.ParamUpdateTime){
      return;
    }

    for(uint256 i = 0; i < SInfo.Packages.length; i++){
      updateFinancialParam(SInfo.Packages[i]);
    }

    SInfo.ParamUpdateTime = block.timestamp;
  }

  function _calcInvestFinancial(uint256 packageID, uint256 amount, uint256 paramCRFI, uint256 paramCFil)
    internal
    view
    returns(uint256 crfiInterest, uint256 cfilInterest){
    
    FinancialPackage storage package = SInfo.Packages[packageID];

    (uint256 packageParamCRFI, uint256 packageParamCFil) = calcFinancialParam(package);
    crfiInterest = amount.mul(packageParamCRFI.sub(paramCRFI)) / Decimal;
    cfilInterest = amount.mul(packageParamCFil.sub(paramCFil)) / Decimal;

    return(crfiInterest, cfilInterest);
  }

  function calcInvestFinancial(QueueData storage data)
    internal
    view
    returns(uint256 crfiInterest, uint256 cfilInterest){
    return _calcInvestFinancial(data.PackageID, data.Amount, data.ParamCRFI, data.ParamCFil);
  }
}
