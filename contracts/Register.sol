// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;
/// @title Storage String
/// @author Imanol Valenzuela Eguez
contract WhiteList{
    string private storedInfo;
    address public owner;
    mapping (address => bool) public whiteList;

    constructor(){
        owner = msg.sender;
        whiteList[msg.sender] = true;
        storedInfo = "Hello world";
    }

    modifier onlyOwner {
        require (msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyWhiteList{
        require(whiteList[msg.sender] == true, "Only  whitelist");
        _;
    }

    function setInfo(string memory mnyInfo) external onlyWhiteList{
        storedInfo = mnyInfo;
    }

    function addMember(address member) external onlyOwner{
        whiteList[member] = true;
    }

    
    function deleteMember(address member) external onlyOwner{
        whiteList[member] = false;
    }

    function getInfo() external view returns (string memory){
        return storedInfo;
    }
}