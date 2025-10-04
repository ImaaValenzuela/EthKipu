// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;
/// @title Storage String
/// @author Imanol Valenzuela Eguez
contract Register{
    string private storedInfo;
/// Store "newInfo"
/// @dev stores the string in the state variable 'storedInfo'
/// @param newInfo the new string to store
    function setInfo(string memory newInfo) external{
        storedInfo = newInfo;
    }

    function getInfo() external view returns (string memory){
        return storedInfo;
    }
}