// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;
/// @title Storage String
/// @author Imanol Valenzuela Eguez
contract FirstArray{
    string[] private storedInfos;

/// Adds new values to the array using push()
/// index returns the position where the value was stored
    function addInfo(string memory myInfo) external returns (uint index) {
        storedInfos.push(myInfo);
        index = storedInfos.length - 1; 
    }

/// Updates the value at the specified index in the array
/// Verifies the position is valid, othewise returns an error
    function updateInfo(uint index, string memory newInfo) external{
        require(index < storedInfos.length, "Invalid Index");
        storedInfos[index] = newInfo;
    }

/// Return the stored value at the index position of the array
/// Check if the position is valid, othewise returns an error
    function getOneInfo(uint index) external view returns (string memory){
        require(index < storedInfos.length, "Invalid Index");
        return storedInfos[index];
    }

/// Returns all values stored in the array
    function listAllInfo() external view returns (string[] memory){
        return storedInfos;
    }
}