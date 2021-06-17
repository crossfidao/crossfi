// SPDX-License-Identifier: PRIVATE
pragma solidity >=0.6.2 <0.8.0;

enum FinancialType{CRFI, CFil}

struct FinancialPackage {
  FinancialType Type;
  
  uint256 Days;
  uint256 CFilInterestRate;
  uint256 CRFIInterestRateDyn;
  uint256 ID;

  uint256 Weight;
  uint256 ParamCRFI;
  uint256 ParamCFil;
  uint256 Total;
}

struct LoanCFilPackage {
  uint256 APY;
  uint256 PledgeRate;
  uint256 PaymentDue;
  uint256 PaymentDue99;

  uint256 UpdateTime;
  uint256 Param;
}

struct ViewSystemInfo{
  FinancialPackage[] Packages;
  uint256 AffRate;
  uint256 AffRequire;
  uint256 EnableAffCFil;
  
  LoanCFilPackage LoanCFil;

  ChainManager ChainM;

  // invest
  uint256 NewInvestID;
  mapping(uint256 => InvestInfo) Invests;
  mapping(address => uint256) InvestAddrID;
        
  // setting power
  address SuperAdmin;
  mapping(address => bool) Admins;

  // statistic
  uint256 nowInvestCRFI;
  uint256 nowInvestCFil; 
  uint256 cfilInterestPool;
  uint256 crfiInterestPool;

  uint256 cfilLendingTotal;
  uint256 crfiRewardTotal;
  uint256 avaiCFilAmount;
  
  uint256 totalWeightCFil;
  uint256 totalWeightCRFI;
  uint256 crfiMinerPerDayCFil;
  uint256 crfiMinerPerDayCRFI;
  
  uint256 ParamUpdateTime;
}

struct SystemInfoView {
  uint256 AffRate;
  uint256 AffRequire;
  uint256 EnableAffCFil;
  
  // invest
  uint256 NewInvestID;

  // statistic
  uint256 nowInvestCRFI;
  uint256 nowInvestCFil; 
  uint256 cfilInterestPool;
  uint256 crfiInterestPool;

  uint256 cfilLendingTotal;
  uint256 crfiRewardTotal;
  uint256 avaiCFilAmount;
  
  uint256 totalWeightCFil;
  uint256 totalWeightCRFI;
  uint256 crfiMinerPerDayCFil;
  uint256 crfiMinerPerDayCRFI;
  
  uint256 ParamUpdateTime;
}

struct SystemInfo {

  FinancialPackage[] Packages;
  uint256 AffRate;
  uint256 AffRequire;
  uint256 EnableAffCFil;
  
  LoanCFilPackage LoanCFil;

  ChainManager ChainM;

  // invest
  uint256 NewInvestID;
  mapping(uint256 => InvestInfo) Invests;
  mapping(address => uint256) InvestAddrID;
        
  // setting power
  address SuperAdmin;
  mapping(address => bool) Admins;

  // statistic
  uint256 nowInvestCRFI;
  uint256 nowInvestCFil; 
  uint256 cfilInterestPool;
  uint256 crfiInterestPool;

  uint256 cfilLendingTotal;
  uint256 crfiRewardTotal;
  uint256 avaiCFilAmount;
  
  uint256 totalWeightCFil;
  uint256 totalWeightCRFI;
  uint256 crfiMinerPerDayCFil;
  uint256 crfiMinerPerDayCRFI;
  
  uint256 ParamUpdateTime;

  mapping(string => string) kvMap;
}

struct InterestDetail{
  uint256 crfiInterest;
  uint256 cfilInterest;
}

struct LoanInvest{
  uint256 Lending;
  uint256 Pledge;
  uint256 Param;
  uint256 NowInterest;
}

struct InvestInfoView {
  address Addr;
  uint256 ID;

  uint256 affID;

  // statistic for financial
  uint256 totalAffTimes;
  uint256 totalAffPackageTimes;
  
  uint256 totalAffCRFI;
  uint256 totalAffCFil;
  
  uint256 nowInvestFinCRFI;
  uint256 nowInvestFinCFil;
}

struct InvestInfo {
  mapping(uint256 => ChainQueue) InvestRecords;

  address Addr;
  uint256 ID;

  uint256 affID;

  LoanInvest LoanCFil;

  // statistic for financial
  uint256 totalAffTimes;
  uint256 totalAffPackageTimes;
  
  uint256 totalAffCRFI;
  uint256 totalAffCFil;
  
  uint256 nowInvestFinCRFI;
  uint256 nowInvestFinCFil;
}


//////////////////// queue

struct QueueData {
  uint256 RecordID;
  
  FinancialType Type;
  uint256 PackageID;
  uint256 Days;
  uint256 EndTime;
  uint256 AffID;
  uint256 Amount;

  uint256 ParamCRFI;
  uint256 ParamCFil;
}

struct ChainItem {
  uint256 Next;
  uint256 Prev;
  uint256 My;
  
  QueueData Data;
}

struct ChainQueue{
  uint256 First;
  uint256 End;

  uint256 Size;
}


struct ChainManager{
  ChainItem[] rawQueue;

  ChainQueue avaiQueue;
}

library ChainQueueLib{

  //////////////////// item
  function GetNullItem(ChainManager storage chainM)
    internal
    view
    returns(ChainItem storage item){
    return chainM.rawQueue[0];
  }

  function HasNext(ChainManager storage chainM,
                   ChainItem storage item)
    internal
    view
    returns(bool has){

    if(item.Next == 0){
      return false;
    }

    return true;
  }

  function Next(ChainManager storage chainM,
                ChainItem storage item)
    internal
    view
    returns(ChainItem storage nextItem){

    uint256 nextIdx = item.Next;
    require(nextIdx > 0, "no next item");

    return chainM.rawQueue[uint256(nextIdx)];
  }

  //////////////////// chain
  function GetFirstItem(ChainManager storage chainM,
                        ChainQueue storage chain)
    internal
    view
    returns(ChainItem storage item){

    require(chain.Size > 0, "chain is empty");

    return chainM.rawQueue[chain.First];
  }

  function GetEndItem(ChainManager storage chainM,
                      ChainQueue storage chain)
    internal
    view
    returns(ChainItem storage item){

    require(chain.Size > 0, "chain is empty");

    return chainM.rawQueue[chain.End];
  }

  // need ensure the item is in chain
  function DeleteItem(ChainManager storage chainM,
                      ChainQueue storage chain,
                      ChainItem storage item)
    internal{

    if(chain.First == item.My){
      PopPutFirst(chainM, chain);
      return;
    } else if (chain.End == item.My){
      PopPutEnd(chainM, chain);
      return;
    }

    ChainItem storage next = chainM.rawQueue[item.Next];
    ChainItem storage prev = chainM.rawQueue[item.Prev];

    next.Prev = item.Prev;
    prev.Next = item.Next;

    item.Prev = 0;
    item.Next = 0;

    chain.Size--;

    PutItem(chainM, item);
  }

  function PopPutFirst(ChainManager storage chainM,
                       ChainQueue storage chain)
    internal{

    ChainItem storage item = PopFirstItem(chainM, chain);
    PutItem(chainM, item);
  }

  function PopPutEnd(ChainManager storage chainM,
                     ChainQueue storage chain)
    internal{

    ChainItem storage item = PopEndItem(chainM, chain);
    PutItem(chainM, item);
  }

  function PopEndItem(ChainManager storage chainM,
                        ChainQueue storage chain)
    internal
    returns(ChainItem storage item){
    
    require(chain.Size >0, "chain is empty");
    
    uint256 itemIdx = chain.End;
    chain.End = chainM.rawQueue[itemIdx].Prev;
    if(chain.End > 0){
      chainM.rawQueue[chain.End].Next = 0;
    } else {
      chain.First = 0;
    }
    chain.Size--;
    item = chainM.rawQueue[itemIdx];
    item.Prev = 0;
    return item;
  }

  function PopFirstItem(ChainManager storage chainM,
                        ChainQueue storage chain)
    internal
    returns(ChainItem storage item){

    require(chain.Size > 0, "chain is empty");

    uint256 itemIdx = chain.First;
    chain.First = chainM.rawQueue[itemIdx].Next;
    if(chain.First > 0){
      chainM.rawQueue[chain.First].Prev = 0;
    } else {
      chain.End = 0;
    }
    chain.Size--;

    item = chainM.rawQueue[itemIdx];
    item.Next = 0;

    return item;
  }

  function PushEndItem(ChainManager storage chainM,
                       ChainQueue storage chain,
                       ChainItem storage item)
    internal{

    item.Prev = chain.End;
    item.Next = 0;

    if(chain.Size == 0){
      chain.First = item.My;
      chain.End = item.My;
    } else {
      chainM.rawQueue[chain.End].Next = item.My;
      chain.End = item.My;
    }
    chain.Size++;
  }

  //////////////////// chain manager
  function InitChainManager(ChainManager storage chainM)
    internal{
    if(chainM.rawQueue.length == 0){
      chainM.rawQueue.push();
    }
  }
  
  function GetAvaiItem(ChainManager storage chainM)
    internal
    returns(ChainItem storage item){
    
    if(chainM.avaiQueue.Size == 0){
      if(chainM.rawQueue.length == 0){
        chainM.rawQueue.push();
      }
      
      uint256 itemIdx = chainM.rawQueue.length;
      chainM.rawQueue.push();

      item = chainM.rawQueue[itemIdx];
      item.Next = 0;
      item.Prev = 0;
      item.My = itemIdx;
      
      return item;
    }

    return PopFirstItem(chainM, chainM.avaiQueue);
  }

  function PutItem(ChainManager storage chainM,
                   ChainItem storage item)
    internal{
    
    PushEndItem(chainM, chainM.avaiQueue, item);
  }
}
  
