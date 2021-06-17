// SPDX-License-Identifier: PRIVATE
pragma solidity >=0.6.2 <0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";

contract CFil is Context, IERC777, IERC20, ReentrancyGuard, IERC777Recipient {
  
  //////////////////// using
  using SafeMath for uint256;
  using Address for address;

  //////////////////// const
  IERC1820Registry constant internal _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
  
  // We inline the result of the following hashes because Solidity doesn't resolve them at compile time.
  // See https://github.com/ethereum/solidity/issues/4024.

  // keccak256("ERC777TokensSender")
  bytes32 constant private _TOKENS_SENDER_INTERFACE_HASH =
    0x29ddb589b1fb5fc7cf394961c1adf5f8c6454761adf795e67fe149f658abe895;

  // keccak256("ERC777TokensRecipient")
  bytes32 constant private _TOKENS_RECIPIENT_INTERFACE_HASH =
    0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

  IERC777 CRFI;

  uint256 constant calcDecimals = 1e18;
  
  //////////////////// for admin
  address public superAdmin;
  mapping(address => uint256) public admins;

  // only effect erc20 interface.
  // when erc777mode equal 0, the erc777 feature is disabled;
  // when erc777mode equal 1, the erc777 feature is enabled by whitelist.
  // when erc777 mode equal 2, the erc777 feature is disabled by blacklist.
  // when erc777 mode equal 3, the erc777 feature is enabled;
  // in whitelist or black list mode, whether "from" or "to" address in list, the feature would be effected.
  enum Erc777ModeType {disabled, whitelist, blacklist, enabled}
  Erc777ModeType public erc777Mode;
  mapping(address=>bool) public blacklist;
  mapping(address=>bool) public whitelist;
  
  //////////////////// for coin
  mapping(address => uint256) private _balances;

  uint256 private _totalSupply;

  string private _name;
  string private _symbol;

  // ERC20-allowances
  mapping (address => mapping (address => uint256)) private _allowances;

  mapping(address=>bool) private _freezeAddress;

  //////////////////// for operator  
  // This isn't ever read from - it's only used to respond to the defaultOperators query.
  address[] private _defaultOperatorsArray;

  // Immutable, but accounts may revoke them (tracked in __revokedDefaultOperators).
  mapping(address => bool) private _defaultOperators;

  // For each account, a mapping of its operators and revoked default operators.
  mapping(address => mapping(address => bool)) private _operators;
  mapping(address => mapping(address => bool)) private _revokedDefaultOperators;

  //////////////////// for burn
  uint256 public burnCFilRateCRFI;
  uint256 public burnCFilFee;

  //////////////////// constructor
  /**
   * @dev `defaultOperators` may be an empty array.
   */
  constructor(address[] memory defaultOperators_,
              address CRFIAddr
              )
      {
        require(CRFIAddr.isContract(), "CRFIAddr error");
        CRFI = IERC777(CRFIAddr);
        _name = "CFIL";
        _symbol = "CFIL";

        _defaultOperatorsArray = defaultOperators_;
        for (uint256 i = 0; i < _defaultOperatorsArray.length; i++) {
          _defaultOperators[_defaultOperatorsArray[i]] = true;
        }

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777Token"), address(this));
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC20Token"), address(this));

        superAdmin = msg.sender;

        // init mode
        ChangeMode(Erc777ModeType.disabled);
        burnCFilRateCRFI = calcDecimals / 100;

        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
      }

  //////////////////// modifier
  modifier IsAdmin() {
    require(msg.sender == superAdmin || admins[msg.sender] == 1, "only admin");
    _;
  }

  modifier IsSuperAdmin() {
    require(superAdmin == msg.sender, "only super admin");
    _;
  }

  modifier CheckFreeze(address addr){
    require(_freezeAddress[addr] == false, "account is freeze");
    _;
  }

  //////////////////// super admin func
  function AddAdmin(address adminAddr)
    public
    IsSuperAdmin(){
    require(admins[adminAddr] == 0, "already add this admin");
    admins[adminAddr] = 1;
  }

  function DelAdmin(address adminAddr)
    public
    IsSuperAdmin(){
    require(admins[adminAddr] == 1, "this addr is not admin");
    admins[adminAddr] = 0;
  }

  function ChangeSuperAdmin(address suAdminAddr)
    public
    IsSuperAdmin(){
    require(suAdminAddr != address(0x0), "empty new super admin");

    superAdmin = suAdminAddr;
  }

  //////////////////// for admin func
  function ChangeBurnCFilRateCRFI(uint256 rate)
    public
    IsAdmin(){

    burnCFilRateCRFI = rate;
  }

  function ChangeBurnCFilFee(uint256 fee)
    public
    IsAdmin(){

    burnCFilFee = fee;
  }
  
  function AddBlackList(address[] memory addrs)
    public
    IsAdmin(){

    for(uint256 i = 0; i < addrs.length; i++){
      address addr = addrs[i];
      if(blacklist[addr]){
        continue;
      }
      blacklist[addr] = true;
    }
  }

  function DelBlackList(address[] memory addrs)
    public
    IsAdmin(){

    for(uint256 i = 0; i < addrs.length; i++){
      address addr = addrs[i];
      if(!blacklist[addr]){
        continue;
      }
      blacklist[addr] = false;
    }
  }

  function AddWhiteList(address[] memory addrs)
    public
    IsAdmin(){

    for(uint256 i = 0; i < addrs.length; i++){
      address addr = addrs[i];
      if(whitelist[addr]){
        continue;
      }
      whitelist[addr] = true;
    }
  }

  function DelWhiteList(address[] memory addrs)
    public
    IsAdmin(){

    for(uint256 i = 0; i < addrs.length; i++){
      address addr = addrs[i];
      if(!whitelist[addr] ){
        continue;
      }
      whitelist[addr] = false;
    }
  }

  function ChangeMode(Erc777ModeType mode)
    public
    IsAdmin(){

    erc777Mode = mode;
  }

  function FreezeAddr(address[] memory addrs)
    public
    IsAdmin(){
    for(uint256 i = 0; i < addrs.length; i++){
      address addr = addrs[i];
      if(_freezeAddress[addr] == true){
        continue;
      }
      _freezeAddress[addr] = true;
    }
  }

  function UnfreezeAddr(address[] memory addrs)
    public
    IsAdmin(){
    for(uint256 i = 0; i < addrs.length; i++){
      address addr = addrs[i];
      if(_freezeAddress[addr] == false){
        continue;
      }
      _freezeAddress[addr] = false;
    }
  }

  //////////////////// event
  event BurnedCRFICFil(address indexed account,
                       uint256 amount,
                       bytes data);



  //////////////////// interface implement
  
  /**
   * @dev See {IERC777-name}.
   */
  function name() public view virtual override returns (string memory) {
    return _name;
  }

  /**
   * @dev See {IERC777-symbol}.
   */
  function symbol() public view virtual override returns (string memory) {
    return _symbol;
  }

  /**
   * @dev See {ERC20-decimals}.
   *
   * Always returns 18, as per the
   * [ERC777 EIP](https://eips.ethereum.org/EIPS/eip-777#backward-compatibility).
   */
  function decimals() public pure virtual returns (uint8) {
    return 18;
  }

  /**
   * @dev See {IERC777-granularity}.
   *
   * This implementation always returns `1`.
   */
  function granularity() public view virtual override returns (uint256) {
    return 1;
  }

  /**
   * @dev See {IERC777-totalSupply}.
   */
  function totalSupply() public view virtual override(IERC20, IERC777) returns (uint256) {
    return _totalSupply;
  }

  /**
   * @dev Returns the amount of tokens owned by an account (`tokenHolder`).
   */
  function balanceOf(address tokenHolder) public view virtual override(IERC20, IERC777) returns (uint256) {
    return _balances[tokenHolder];
  }

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

    require(msg.sender == address(CRFI), "only receive CRFI");
    require(burnCFilRateCRFI > 0, "burn cfil rate CRFI is zero, should use burn directly");

    uint256 burnCFil = _calcBurnCFil(amount);
    require(balanceOf(from) >= burnCFil, "not enough cfil");

    _burn(from, burnCFil, userData, operatorData);
    CRFI.burn(amount, userData);

    // for ensure call this method;
    _emitBurn(from, burnCFil, userData);
  }

  /**
   * @dev See {IERC777-send}.
   *
   * Also emits a {IERC20-Transfer} event for ERC20 compatibility.
   */
  function send(address recipient, uint256 amount, bytes memory data) public virtual override  CheckFreeze(_msgSender()){
    _send(_msgSender(), recipient, amount, data, "", true);
  }

  /**
   * @dev See {IERC20-transfer}.
   *
   * Unlike `send`, `recipient` is _not_ required to implement the {IERC777Recipient}
   * interface if it is a contract.
   *
   * Also emits a {Sent} event.
   */
  function transfer(address recipient, uint256 amount)
    public
    virtual
    override
    CheckFreeze(_msgSender())
    returns (bool) {
    require(recipient != address(0), "ERC777: transfer to the zero address");

    address from = _msgSender();

    bool erc777Enable = _enableERC777(from, recipient);

    if(erc777Enable){
      _callTokensToSend(from, from, recipient, amount, "", "");
    }

    _move(from, from, recipient, amount, "", "", erc777Enable);

    if(erc777Enable){
      _callTokensReceived(from, from, recipient, amount, "", "", false);
    }

    return true;
  }

  /**
   * @dev See {IERC777-burn}.
   *
   * Also emits a {IERC20-Transfer} event for ERC20 compatibility.
   */
  function burn(uint256 amount, bytes memory data) public virtual override  CheckFreeze(_msgSender()){
    _burn(_msgSender(), amount, data, "");
    if(burnCFilRateCRFI == 0){
      _emitBurn(_msgSender(), amount, data);
    }
  }

  /**
   * @dev See {IERC777-isOperatorFor}.
   */
  function isOperatorFor(address operator, address tokenHolder) public view virtual override returns (bool) {
    return operator == tokenHolder ||
      (_defaultOperators[operator] && !_revokedDefaultOperators[tokenHolder][operator]) ||
      _operators[tokenHolder][operator];
  }

  /**
   * @dev See {IERC777-authorizeOperator}.
   */
  function authorizeOperator(address operator) public virtual override  {
    require(_msgSender() != operator, "ERC777: authorizing self as operator");

    if (_defaultOperators[operator]) {
      delete _revokedDefaultOperators[_msgSender()][operator];
    } else {
      _operators[_msgSender()][operator] = true;
    }

    emit AuthorizedOperator(operator, _msgSender());
  }

  /**
   * @dev See {IERC777-revokeOperator}.
   */
  function revokeOperator(address operator) public virtual override  {
    require(operator != _msgSender(), "ERC777: revoking self as operator");

    if (_defaultOperators[operator]) {
      _revokedDefaultOperators[_msgSender()][operator] = true;
    } else {
      delete _operators[_msgSender()][operator];
    }

    emit RevokedOperator(operator, _msgSender());
  }

  /**
   * @dev See {IERC777-defaultOperators}.
   */
  function defaultOperators() public view virtual override returns (address[] memory) {
    return _defaultOperatorsArray;
  }

  /**
   * @dev See {IERC777-operatorSend}.
   *
   * Emits {Sent} and {IERC20-Transfer} events.
   */
  function operatorSend(
                        address sender,
                        address recipient,
                        uint256 amount,
                        bytes memory data,
                        bytes memory operatorData
                        )
    public
    virtual
    override
    CheckFreeze(sender)
  {
    require(isOperatorFor(_msgSender(), sender), "ERC777: caller is not an operator for holder");
    _send(sender, recipient, amount, data, operatorData, true);
  }

  /**
   * @dev See {IERC777-operatorBurn}.
   *
   * Emits {Burned} and {IERC20-Transfer} events.
   */
  function operatorBurn(address account, uint256 amount, bytes memory data, bytes memory operatorData) public virtual override CheckFreeze(account){
    require(isOperatorFor(_msgSender(), account), "ERC777: caller is not an operator for holder");
    _burn(account, amount, data, operatorData);
  }

  /**
   * @dev See {IERC20-allowance}.
   *
   * Note that operator and allowance concepts are orthogonal: operators may
   * not have allowance, and accounts with allowance may not be operators
   * themselves.
   */
  function allowance(address holder, address spender) public view virtual override returns (uint256) {
    return _allowances[holder][spender];
  }

  /**
   * @dev See {IERC20-approve}.
   *
   * Note that accounts cannot have allowance issued by their operators.
   */
  function approve(address spender, uint256 value) public virtual override returns (bool) {
    address holder = _msgSender();
    _approve(holder, spender, value);
    return true;
  }

  /**
   * @dev See {IERC20-transferFrom}.
   *
   * Note that operator and allowance concepts are orthogonal: operators cannot
   * call `transferFrom` (unless they have allowance), and accounts with
   * allowance cannot call `operatorSend` (unless they are operators).
   *
   * Emits {Sent}, {IERC20-Transfer} and {IERC20-Approval} events.
   */
  function transferFrom(address holder, address recipient, uint256 amount) public virtual override CheckFreeze(holder) returns (bool) {
    require(recipient != address(0), "ERC777: transfer to the zero address");
    require(holder != address(0), "ERC777: transfer from the zero address");

    address spender = _msgSender();

    bool erc777Enable = _enableERC777(holder, recipient);

    if(erc777Enable){
      _callTokensToSend(spender, holder, recipient, amount, "", "");
    }

    _move(spender, holder, recipient, amount, "", "", erc777Enable);
    _approve(holder, spender, _allowances[holder][spender].sub(amount, "ERC777: transfer amount exceeds allowance"));

    if(erc777Enable){
      _callTokensReceived(spender, holder, recipient, amount, "", "", false);
    }

    return true;
  }

  function mint(address account,
                uint256 amount,
                bytes memory userData)
    public
    IsAdmin(){
    _mint(account, amount, userData, "");
  }
  
  /**
   * @dev Creates `amount` tokens and assigns them to `account`, increasing
   * the total supply.
   *
   * If a send hook is registered for `account`, the corresponding function
   * will be called with `operator`, `data` and `operatorData`.
   *
   * See {IERC777Sender} and {IERC777Recipient}.
   *
   * Emits {Minted} and {IERC20-Transfer} events.
   *
   * Requirements
   *
   * - `account` cannot be the zero address.
   * - if `account` is a contract, it must implement the {IERC777Recipient}
   * interface.
   */
  function _mint(
                 address account,
                 uint256 amount,
                 bytes memory userData,
                 bytes memory operatorData
                 )
    internal
    virtual
  {
    require(account != address(0), "ERC777: mint to the zero address");

    address operator = _msgSender();

    _beforeTokenTransfer(operator, address(0), account, amount);

    // Update state variables
    _totalSupply = _totalSupply.add(amount);
    _balances[account] = _balances[account].add(amount);

    _callTokensReceived(operator, address(0), account, amount, userData, operatorData, true);

    emit Minted(operator, account, amount, userData, operatorData);
    emit Transfer(address(0), account, amount);
  }

  /**
   * @dev Send tokens
   * @param from address token holder address
   * @param to address recipient address
   * @param amount uint256 amount of tokens to transfer
   * @param userData bytes extra information provided by the token holder (if any)
   * @param operatorData bytes extra information provided by the operator (if any)
   * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
   */
  function _send(
                 address from,
                 address to,
                 uint256 amount,
                 bytes memory userData,
                 bytes memory operatorData,
                 bool requireReceptionAck
                 )
    internal
    virtual
  {
    require(from != address(0), "ERC777: send from the zero address");
    require(to != address(0), "ERC777: send to the zero address");

    address operator = _msgSender();

    _callTokensToSend(operator, from, to, amount, userData, operatorData);

    _move(operator, from, to, amount, userData, operatorData, true);

    _callTokensReceived(operator, from, to, amount, userData, operatorData, requireReceptionAck);
  }

  /**
   * @dev Burn tokens
   * @param from address token holder address
   * @param amount uint256 amount of tokens to burn
   * @param data bytes extra information provided by the token holder
   * @param operatorData bytes extra information provided by the operator (if any)
   */
  function _burn(
                 address from,
                 uint256 amount,
                 bytes memory data,
                 bytes memory operatorData
                 )
    internal
    virtual
  {
    require(from != address(0), "ERC777: burn from the zero address");

    address operator = _msgSender();

    _callTokensToSend(operator, from, address(0), amount, data, operatorData);

    _beforeTokenTransfer(operator, from, address(0), amount);

    // Update state variables
    _balances[from] = _balances[from].sub(amount, "ERC777: burn amount exceeds balance");
    _totalSupply = _totalSupply.sub(amount);

    emit Burned(operator, from, amount, data, operatorData);
    emit Transfer(from, address(0), amount);
  }

  function _move(
                 address operator,
                 address from,
                 address to,
                 uint256 amount,
                 bytes memory userData,
                 bytes memory operatorData,
                 bool erc777Enable
                 )
    private
  {
    if(erc777Enable){
      _beforeTokenTransfer(operator, from, to, amount);
    }

    _balances[from] = _balances[from].sub(amount, "ERC777: transfer amount exceeds balance");
    _balances[to] = _balances[to].add(amount);

    emit Sent(operator, from, to, amount, userData, operatorData);
    emit Transfer(from, to, amount);
  }

  /**
   * @dev See {ERC20-_approve}.
   *
   * Note that accounts cannot have allowance issued by their operators.
   */
  function _approve(address holder, address spender, uint256 value) internal {
    require(holder != address(0), "ERC777: approve from the zero address");
    require(spender != address(0), "ERC777: approve to the zero address");

    _allowances[holder][spender] = value;
    emit Approval(holder, spender, value);
  }

  /**
   * @dev Call from.tokensToSend() if the interface is registered
   * @param operator address operator requesting the transfer
   * @param from address token holder address
   * @param to address recipient address
   * @param amount uint256 amount of tokens to transfer
   * @param userData bytes extra information provided by the token holder (if any)
   * @param operatorData bytes extra information provided by the operator (if any)
   */
  function _callTokensToSend(
                             address operator,
                             address from,
                             address to,
                             uint256 amount,
                             bytes memory userData,
                             bytes memory operatorData
                             )
    private
  {
    address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(from, _TOKENS_SENDER_INTERFACE_HASH);
    if (implementer != address(0)) {
      IERC777Sender(implementer).tokensToSend(operator, from, to, amount, userData, operatorData);
    }
  }

  /**
   * @dev Call to.tokensReceived() if the interface is registered. Reverts if the recipient is a contract but
   * tokensReceived() was not registered for the recipient
   * @param operator address operator requesting the transfer
   * @param from address token holder address
   * @param to address recipient address
   * @param amount uint256 amount of tokens to transfer
   * @param userData bytes extra information provided by the token holder (if any)
   * @param operatorData bytes extra information provided by the operator (if any)
   * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
   */
  function _callTokensReceived(
                               address operator,
                               address from,
                               address to,
                               uint256 amount,
                               bytes memory userData,
                               bytes memory operatorData,
                               bool requireReceptionAck
                               )
    private
  {
    address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(to, _TOKENS_RECIPIENT_INTERFACE_HASH);
    if (implementer != address(0)) {
      IERC777Recipient(implementer).tokensReceived(operator, from, to, amount, userData, operatorData);
    } else if (requireReceptionAck) {
      require(!to.isContract(), "ERC777: token recipient contract has no implementer for ERC777TokensRecipient");
    }
  }

  /**
   * @dev Hook that is called before any token transfer. This includes
   * calls to {send}, {transfer}, {operatorSend}, minting and burning.
   *
   * Calling conditions:
   *
   * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
   * will be to transferred to `to`.
   * - when `from` is zero, `amount` tokens will be minted for `to`.
   * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
   * - `from` and `to` are never both zero.
   *
   * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
   */
  function _beforeTokenTransfer(address operator, address from, address to, uint256 amount) internal virtual { }

  
  function _enableERC777(address from, address to)
    internal
    view
    returns(bool){

    if(erc777Mode == Erc777ModeType.disabled){
      return false;
    }

    if(erc777Mode == Erc777ModeType.enabled){
      return true;
    }

    if(erc777Mode == Erc777ModeType.whitelist){
      return whitelist[from] || whitelist[to];
    }

    if(erc777Mode == Erc777ModeType.blacklist){
      return (!blacklist[from]) && (!blacklist[to]);
    }

    return false;
  }

  function _calcBurnCFil(uint256 CRFINum)
    public
    view
    returns(uint256 CFilNum){

    return CRFINum.mul(calcDecimals) / burnCFilRateCRFI;
  }

  function _calcNeedBurnCRFI(uint256 CFilNum)
    public
    view
    returns(uint256 CRFINum){

    return CFilNum.mul(burnCFilRateCRFI) / calcDecimals;
  }

  function _emitBurn(address from, uint256 amount, bytes memory data)
    internal{

    require(amount >= burnCFilFee, "amount <= burnCFilFee");
    require(data.length > 0, "no user data");

    amount = amount.sub(burnCFilFee);

    if(amount > 0){
      emit BurnedCRFICFil(from, amount, data);
    }
  }
}
