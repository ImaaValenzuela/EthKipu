// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;
/// @title Storage String
/// @author Imanol Valenzuela Eguez
contract Owner{
    string private storedInfo;
    address public owner;
/// The constructor set the deployer as the owner
    constructor(){
        owner = msg.sender;
    }

/// setInfo function checks if the transaction sender
/// is the contract owner. If verified, it modifies the variable value
/// If not, the function reverts or does nothing
    function setInfo(string memory newInfo) external{
        require(msg.sender == owner, "Only the owner can update the info");
        storedInfo = newInfo;
    }

// Return the stored string
// @dev retrieves the string of the state variable storedInfo
// @return the stored string
    function getInfo() external view returns (string memory){
        return storedInfo;
    }
}