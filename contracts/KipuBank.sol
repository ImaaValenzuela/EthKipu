// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;
/// @title Storage String
/// @author Imanol Valenzuela Eguez
contract KipuBank{
    uint256 public immutable WITHDRAWAL_LIMIT;

    uint256 public constant MINIMUM_DEPOSIT =  0.001 ether;

    uint256 public bankCap = 10 ether;

    uint256 public totalDeposits;

    uint256 public depositCount;

    uint256 public withdrawalCount;

    mapping(address => uint256) public vaults;

    event Deposit(address indexed user, uint256 amount, uint256 newBalance);

    event Withdrawal(address indexed user, uint256 amount, uint256 newBalance);

    error DepositTooSmall();

    error BankCapExceeded();

    error InsufficientBalance();

    error WithdrawalLimitExceeded();

    error TransferFailed();

    error InvalidWithdrawalAmount();

    constructor(uint256 _bankCap, uint256 _withdrawalLimit){
        bankCap = _bankCap;
        WITHDRAWAL_LIMIT = _withdrawalLimit;
    }

    modifier validAmount(uint256 amount){
        if (amount == 0) revert InvalidWithdrawalAmount();
        _;
    }

    function deposit() external payable {
        if (msg.value < MINIMUM_DEPOSIT) revert DepositTooSmall();
        if (totalDeposits + msg.value > bankCap) revert BankCapExceeded();

        vaults[msg.sender] += msg.value;
        totalDeposits += msg.value;
        depositCount++;

        emit Deposit(msg.sender, msg.value, vaults[msg.sender]);
    }

    function withdraw(uint256 amount) external validAmount(amount){
        if (vaults[msg.sender] < amount) revert InsufficientBalance();
        if(amount > WITHDRAWAL_LIMIT) revert WithdrawalLimitExceeded();

        vaults[msg.sender] -= amount;
        totalDeposits -= amount;
        withdrawalCount++;

        _sendEther(msg.sender, amount);

        emit Withdrawal(msg.sender, amount, vaults[msg.sender]);
    }

    function getBalance(address user) external view returns (uint256){
        return vaults[user];
    }

    function getBankStats() external view returns (
        uint256 _totalDeposits,
        uint256 _depositCount,
        uint256 _withdrawalCount,
        uint256 _avalaibleCapacity
    ){
        return (
            totalDeposits,
            depositCount,
            withdrawalCount,
            bankCap - totalDeposits
        );
    }

    function _sendEther(address to, uint256 amount) private{
        (bool success, ) = to.call{value: amount}("");
        if(!success) revert TransferFailed();
    }
}