// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;
/// @title Storage String
/// @author Imanol Valenzuela Eguez
contract ChangeCounter{
    string private storedInfo;
    uint public countChanges = 0;
/// Store "newInfo"
/// Increase the counter which manage how many times storedInfo is updated
/// @dev stores the string in the state variable 'storedInfo'
/// @param newInfo the new string to store
    function setInfo(string memory newInfo) external{
        storedInfo = newInfo;
        countChanges++;
    }

// Return the stored string
// @dev retrieves the string of the state variable storedInfo
// @return the stored string
    function getInfo() external view returns (string memory){
        return storedInfo;
    }
}