// SPDX-License-Identifier: PRIVATE
pragma solidity >=0.7.0 <0.8.0;

import "./main.sol";
import "./data.sol";

contract CrossLendDebug is CrossLend {

  constructor(address crfiAddr, address cfilAddr, address sfilAddr)
    CrossLend(crfiAddr, cfilAddr, sfilAddr){

    // OneDayTime = 60 * 60 * 24;
    OneDayTime = 60 * 5;

    uint256 crfi_days = 0;
    uint256 cfil_days = 0;
    for(uint256 i = 0; i < SInfo.Packages.length; i++){
      if(SInfo.Packages[i].Type == FinancialType.CRFI){
        SInfo.Packages[i].Days = crfi_days;
        crfi_days++;
      }else {
        SInfo.Packages[i].Days = cfil_days;
        cfil_days++;
      }
    }
  }

  uint256 public debugFlag = 1;

  function nowTime()
    public
    view
    returns(uint256){
    return block.timestamp;
  }
}
