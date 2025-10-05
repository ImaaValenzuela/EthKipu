// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;
/// @title Storage String
/// @author Imanol Valenzuela Eguez
contract AllTogether{
    enum Colors {Undefined, Blue, Red}

    struct InfoStruct{
        string info;
        Colors color;
        uint countChanges;
    }

    mapping (address => InfoStruct[]) public storedInfos;

    constructor(){
        InfoStruct memory auxInfo = InfoStruct({
            info: "Hello world",
            color: Colors.Undefined,
            countChanges: 0
        });
        storedInfos[msg.sender].push(auxInfo);
    }

    event InfoChange(address person, uint countChamges, string oldInfo, string newInfo);

    function addInfo(Colors myColor, string memory myInfo) public returns (uint index){
        InfoStruct memory auxInfo = InfoStruct({
            info: myInfo,
            color: myColor,
            countChanges: 0
        });
        storedInfos[msg.sender].push(auxInfo);
        return storedInfos[msg.sender].length - 1;
    }

    function setInfo(uint index, string memory newInfo) public {
        storedInfos[msg.sender][index].countChanges++;
        emit InfoChange(msg.sender, storedInfos[msg.sender][index].countChanges, storedInfos[msg.sender][index].info, newInfo);
        storedInfos[msg.sender][index].info = newInfo;
    }

    function setColor(uint index, Colors myColor) public {
        storedInfos[msg.sender][index].color = myColor;
        storedInfos[msg.sender][index].countChanges++;
    }

    function getOneInfo(address account, uint index) public view returns (InfoStruct memory) {
        require(index < storedInfos[account].length, "Invalid index");
        return storedInfos[account][index];
    }

    function getMyInfoAtIndex(uint index) external view returns (InfoStruct memory){
        return getOneInfo(msg.sender, index);
    }

    function listAllInfo(address account) external view returns (InfoStruct[] memory){
        return storedInfos[account];
    }
}