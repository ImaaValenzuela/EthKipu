// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KipuBankV3.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice Token ERC20 de prueba
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;
    
    constructor(string memory name, string memory symbol, uint8 decimals_) 
        ERC20(name, symbol) 
    {
        _decimals = decimals_;
    }
    
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title MockUniswapRouter
 * @notice Router de Uniswap simplificado para testing
 */
contract MockUniswapRouter is IUniswapV2Router02 {
    address public immutable override WETH;
    address public immutable usdc;
    
    // Precio fijo para testing: 1 ETH = 2000 USDC, 1 LINK = 15 USDC
    uint256 public constant ETH_PRICE = 2000;
    uint256 public constant LINK_PRICE = 15;
    
    constructor(address _weth, address _usdc) {
        WETH = _weth;
        usdc = _usdc;
    }
    
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external payable override returns (uint256[] memory amounts) {
        require(path[0] == WETH, "Invalid path");
        require(path[path.length - 1] == usdc, "Must swap to USDC");
        
        // Calcular USDC a recibir (1 ETH = 2000 USDC)
        uint256 usdcAmount = (msg.value * ETH_PRICE * 1e6) / 1e18;
        require(usdcAmount >= amountOutMin, "Slippage exceeded");
        
        // Mint USDC al destinatario
        MockERC20(usdc).mint(to, usdcAmount);
        
        amounts = new uint256[](2);
        amounts[0] = msg.value;
        amounts[1] = usdcAmount;
    }
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /* deadline */
    ) external override returns (uint256[] memory amounts) {
        require(path[path.length - 1] == usdc, "Must swap to USDC");
        
        // Simular swap (ej: LINK → USDC)
        // Transferir tokens de entrada del msg.sender a este contrato
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        
        // Calcular USDC (asumiendo LINK = $15)
        uint256 usdcAmount = (amountIn * LINK_PRICE * 1e6) / 1e18;
        require(usdcAmount >= amountOutMin, "Slippage exceeded");
        
        // Mint USDC al destinatario
        MockERC20(usdc).mint(to, usdcAmount);
        
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[amounts.length - 1] = usdcAmount;
    }
    
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view override returns (uint256[] memory amounts) {
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        
        if (path[0] == WETH) {
            // ETH → USDC
            amounts[amounts.length - 1] = (amountIn * ETH_PRICE * 1e6) / 1e18;
        } else {
            // Token → USDC (asumiendo LINK)
            amounts[amounts.length - 1] = (amountIn * LINK_PRICE * 1e6) / 1e18;
        }
    }
}

/**
 * @title KipuBankV3Test
 * @notice Suite completa de tests para KipuBankV3
 */
contract KipuBankV3Test is Test {
    KipuBankV3 public bank;
    MockUniswapRouter public router;
    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public link;
    
    address public admin = address(1);
    address public operator = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    
    uint256 constant BANK_CAP = 100_000_000000; // 100k USDC
    uint256 constant WITHDRAWAL_LIMIT = 10_000_000000; // 10k USDC
    
    bytes32 constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    event Deposit(address indexed user, address indexed tokenIn, uint256 amountIn, uint256 amountUsdc);
    event Withdrawal(address indexed user, uint256 amount);
    event Swap(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event TokenAllowed(address indexed token, address[] path);

    function setUp() public {
        // Setup tokens
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        link = new MockERC20("Chainlink", "LINK", 18);
        
        // Setup router
        router = new MockUniswapRouter(address(weth), address(usdc));
        
        // Fund users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        
        // Mint tokens to users
        usdc.mint(user1, 50_000_000000); // 50k USDC
        usdc.mint(user2, 50_000_000000);
        link.mint(user1, 1000 ether); // 1000 LINK
        link.mint(user2, 1000 ether);
        
        // Deploy bank
        vm.prank(admin);
        bank = new KipuBankV3(
            address(router),
            address(usdc),
            BANK_CAP,
            WITHDRAWAL_LIMIT
        );
    }
    
    /* ========== DEPLOYMENT TESTS ========== */
    
    function testDeployment() public view {
        assertEq(bank.bankCap(), BANK_CAP);
        assertEq(bank.withdrawalLimit(), WITHDRAWAL_LIMIT);
        assertEq(bank.USDC(), address(usdc));
        assertEq(address(bank.uniswapRouter()), address(router));
        assertTrue(bank.hasRole(bank.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(bank.hasRole(ADMIN_ROLE, admin));
    }
    
    function testUSDCAndNativeAllowedByDefault() public view {
        assertTrue(bank.isTokenAllowed(address(usdc)));
        assertTrue(bank.isTokenAllowed(address(0)));
    }
    
    function testCannotDeployWithZeroAddress() public {
        vm.expectRevert(KipuBankV3.InvalidAddress.selector);
        new KipuBankV3(address(0), address(usdc), BANK_CAP, WITHDRAWAL_LIMIT);
    }
    
    /* ========== DEPOSIT NATIVE TESTS ========== */
    
    function testDepositNative() public {
        uint256 depositAmount = 1 ether;
        uint256 expectedUsdc = 2000_000000; // 1 ETH = 2000 USDC
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, address(0), depositAmount, expectedUsdc);
        
        bank.depositNative{value: depositAmount}();
        
        assertEq(bank.getBalance(user1), expectedUsdc);
        assertEq(bank.totalDeposits(), expectedUsdc);
        assertEq(bank.depositCount(), 1);
    }
    
    function testCannotDepositZeroNative() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.InvalidAmount.selector);
        bank.depositNative{value: 0}();
    }
    
    function testDepositNativeBelowMinimum() public {
        // 0.00001 ETH = 0.02 USDC < 0.1 USDC minimum
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.DepositTooSmall.selector);
        bank.depositNative{value: 0.00001 ether}();
    }
    
    function testDepositNativeExceedsBankCap() public {
        // 51 ETH = 102k USDC > 100k bank cap
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.BankCapExceeded.selector);
        bank.depositNative{value: 51 ether}();
    }
    
    function testMultipleNativeDeposits() public {
        vm.startPrank(user1);
        bank.depositNative{value: 1 ether}(); // 2000 USDC
        bank.depositNative{value: 0.5 ether}(); // 1000 USDC
        vm.stopPrank();
        
        assertEq(bank.getBalance(user1), 3000_000000);
        assertEq(bank.depositCount(), 2);
    }
    
    /* ========== DEPOSIT USDC TESTS ========== */
    
    function testDepositUSDCDirectly() public {
        uint256 amount = 1000_000000; // 1000 USDC
        
        vm.startPrank(user1);
        usdc.approve(address(bank), amount);
        
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, address(usdc), amount, amount);
        
        bank.deposit(address(usdc), amount);
        vm.stopPrank();
        
        assertEq(bank.getBalance(user1), amount);
        assertEq(usdc.balanceOf(address(bank)), amount);
    }
    
    function testCannotDepositUSDCWithoutApproval() public {
        vm.prank(user1);
        vm.expectRevert();
        bank.deposit(address(usdc), 1000_000000);
    }
    
    function testCannotDepositZeroUSDC() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.InvalidAmount.selector);
        bank.deposit(address(usdc), 0);
    }
    
    /* ========== DEPOSIT TOKEN WITH SWAP TESTS ========== */
    
    function testAllowToken() public {
        address[] memory emptyPath = new address[](0);
        
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit TokenAllowed(address(link), emptyPath);
        
        bank.allowToken(address(link), emptyPath);
        
        assertTrue(bank.isTokenAllowed(address(link)));
    }
    
    function testCannotAllowTokenAsNonAdmin() public {
        address[] memory emptyPath = new address[](0);
        
        vm.prank(user1);
        vm.expectRevert();
        bank.allowToken(address(link), emptyPath);
    }
    
    function testDepositTokenWithSwap() public {
        // Allow LINK
        vm.prank(admin);
        address[] memory emptyPath = new address[](0);
        bank.allowToken(address(link), emptyPath);
        
        // Deposit 10 LINK
        uint256 linkAmount = 10 ether;
        uint256 expectedUsdc = 150_000000; // 10 LINK * $15 = 150 USDC
        
        vm.startPrank(user1);
        link.approve(address(bank), linkAmount);
        
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, address(link), linkAmount, expectedUsdc);
        
        bank.deposit(address(link), linkAmount);
        vm.stopPrank();
        
        assertEq(bank.getBalance(user1), expectedUsdc);
    }
    
    function testCannotDepositNotAllowedToken() public {
        // LINK not allowed yet
        vm.startPrank(user1);
        link.approve(address(bank), 10 ether);
        
        vm.expectRevert(KipuBankV3.TokenNotAllowed.selector);
        bank.deposit(address(link), 10 ether);
        vm.stopPrank();
    }
    
    /* ========== WITHDRAWAL TESTS ========== */
    
    function testWithdraw() public {
        // Deposit first
        vm.startPrank(user1);
        usdc.approve(address(bank), 5000_000000);
        bank.deposit(address(usdc), 5000_000000);
        
        // Withdraw
        uint256 withdrawAmount = 1000_000000;
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(user1, withdrawAmount);
        
        bank.withdraw(withdrawAmount);
        vm.stopPrank();
        
        assertEq(bank.getBalance(user1), 4000_000000);
        assertEq(usdc.balanceOf(user1), 46_000_000000); // 50k - 5k + 1k
    }
    
    function testCannotWithdrawZero() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.InvalidAmount.selector);
        bank.withdraw(0);
    }
    
    function testCannotWithdrawMoreThanBalance() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.InsufficientBalance.selector);
        bank.withdraw(1000_000000);
    }
    
    function testCannotWithdrawMoreThanLimit() public {
        // Deposit more than limit
        vm.startPrank(user1);
        usdc.approve(address(bank), 20_000_000000);
        bank.deposit(address(usdc), 20_000_000000);
        
        // Try to withdraw more than limit
        vm.expectRevert(KipuBankV3.WithdrawalLimitExceeded.selector);
        bank.withdraw(11_000_000000); // > 10k limit
        vm.stopPrank();
    }
    
    function testWithdrawAll() public {
        // Deposit 5000 USDC
        vm.startPrank(user1);
        usdc.approve(address(bank), 5000_000000);
        bank.deposit(address(usdc), 5000_000000);
        
        // Withdraw all
        bank.withdrawAll();
        vm.stopPrank();
        
        assertEq(bank.getBalance(user1), 0);
    }
    
    function testWithdrawAllRespectsLimit() public {
        // Deposit 15k USDC (more than withdrawal limit)
        vm.startPrank(user1);
        usdc.approve(address(bank), 15_000_000000);
        bank.deposit(address(usdc), 15_000_000000);
        
        // Withdraw all (should only withdraw 10k due to limit)
        bank.withdrawAll();
        vm.stopPrank();
        
        assertEq(bank.getBalance(user1), 5_000_000000); // 15k - 10k
    }
    
    /* ========== SLIPPAGE TESTS ========== */
    
    function testUpdateSlippage() public {
        uint256 newSlippage = 500; // 5%
        
        vm.prank(admin);
        bank.updateSlippage(newSlippage);
        
        assertEq(bank.slippageTolerance(), newSlippage);
    }
    
    function testCannotUpdateSlippageAboveMax() public {
        vm.prank(admin);
        vm.expectRevert(KipuBankV3.InvalidSlippage.selector);
        bank.updateSlippage(501); // > 5% max
    }
    
    function testCannotUpdateSlippageAsNonAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        bank.updateSlippage(300);
    }
    
    /* ========== PAUSE TESTS ========== */
    
    function testPause() public {
        vm.prank(admin);
        bank.pause();
        
        assertTrue(bank.paused());
    }
    
    function testCannotDepositWhenPaused() public {
        vm.prank(admin);
        bank.pause();
        
        vm.prank(user1);
        vm.expectRevert();
        bank.depositNative{value: 1 ether}();
    }
    
    function testCannotWithdrawWhenPaused() public {
        // Deposit first
        vm.startPrank(user1);
        usdc.approve(address(bank), 1000_000000);
        bank.deposit(address(usdc), 1000_000000);
        vm.stopPrank();
        
        // Pause
        vm.prank(admin);
        bank.pause();
        
        // Try withdraw
        vm.prank(user1);
        vm.expectRevert();
        bank.withdraw(500_000000);
    }
    
    function testUnpause() public {
        vm.startPrank(admin);
        bank.pause();
        bank.unpause();
        vm.stopPrank();
        
        assertFalse(bank.paused());
    }
    
    /* ========== VIEW FUNCTION TESTS ========== */
    
    function testGetBalance() public {
        vm.startPrank(user1);
        usdc.approve(address(bank), 1000_000000);
        bank.deposit(address(usdc), 1000_000000);
        vm.stopPrank();
        
        assertEq(bank.getBalance(user1), 1000_000000);
        assertEq(bank.getBalance(user2), 0);
    }
    
    function testGetBankStats() public {
        // Deposit from user1
        vm.startPrank(user1);
        usdc.approve(address(bank), 5000_000000);
        bank.deposit(address(usdc), 5000_000000);
        vm.stopPrank();
        
        // Deposit from user2
        vm.startPrank(user2);
        usdc.approve(address(bank), 3000_000000);
        bank.deposit(address(usdc), 3000_000000);
        vm.stopPrank();
        
        (uint256 total, uint256 deposits, uint256 withdrawals, uint256 available) = 
            bank.getBankStats();
        
        assertEq(total, 8000_000000);
        assertEq(deposits, 2);
        assertEq(withdrawals, 0);
        assertEq(available, BANK_CAP - 8000_000000);
    }
    
    function testEstimateSwap() public {
        // Allow LINK
        vm.prank(admin);
        address[] memory emptyPath = new address[](0);
        bank.allowToken(address(link), emptyPath);
        
        // Estimate 10 LINK → USDC
        uint256 estimated = bank.estimateSwap(address(link), 10 ether);
        assertEq(estimated, 150_000000); // 10 * $15
    }
    
    function testEstimateSwapForUSDC() public {
        uint256 amount = 1000_000000;
        uint256 estimated = bank.estimateSwap(address(usdc), amount);
        assertEq(estimated, amount); // USDC returns same amount
    }
    
    function testGetSwapPath() public {
        // Allow LINK with custom path
        vm.prank(admin);
        address[] memory customPath = new address[](3);
        customPath[0] = address(link);
        customPath[1] = address(weth);
        customPath[2] = address(usdc);
        bank.allowToken(address(link), customPath);
        
        address[] memory retrievedPath = bank.getSwapPath(address(link));
        assertEq(retrievedPath.length, 3);
        assertEq(retrievedPath[0], address(link));
        assertEq(retrievedPath[1], address(weth));
        assertEq(retrievedPath[2], address(usdc));
    }
    
    /* ========== RECEIVE/FALLBACK TESTS ========== */
    
    function testReceiveFunction() public {
        uint256 amount = 1 ether;
        
        vm.prank(user1);
        (bool success, ) = address(bank).call{value: amount}("");
        
        assertTrue(success);
        assertEq(bank.getBalance(user1), 2000_000000); // 1 ETH = 2000 USDC
    }
    
    function testFallbackFunction() public {
        uint256 amount = 0.5 ether;
        
        vm.prank(user1);
        (bool success, ) = address(bank).call{value: amount}(
            abi.encodeWithSignature("nonExistentFunction()")
        );
        
        assertTrue(success);
        assertEq(bank.getBalance(user1), 1000_000000); // 0.5 ETH = 1000 USDC
    }
    
    /* ========== FUZZ TESTS ========== */
    
    function testFuzzDepositNative(uint96 amount) public {
        vm.assume(amount > 0.00005 ether); // > minimum
        vm.assume(amount < 50 ether); // < bank cap
        
        vm.deal(user1, amount);
        vm.prank(user1);
        bank.depositNative{value: amount}();
        
        assertTrue(bank.getBalance(user1) > 0);
    }
    
    function testFuzzDepositUSDC(uint96 amount) public {
        vm.assume(amount >= 100000); // >= minimum (0.1 USDC)
        vm.assume(amount <= BANK_CAP);
        
        usdc.mint(user1, amount);
        
        vm.startPrank(user1);
        usdc.approve(address(bank), amount);
        bank.deposit(address(usdc), amount);
        vm.stopPrank();
        
        assertEq(bank.getBalance(user1), amount);
    }
    
    function testFuzzWithdraw(uint96 depositAmount, uint96 withdrawAmount) public {
        vm.assume(depositAmount >= 100000 && depositAmount <= 50_000_000000);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);
        vm.assume(withdrawAmount <= WITHDRAWAL_LIMIT);
        
        usdc.mint(user1, depositAmount);
        
        vm.startPrank(user1);
        usdc.approve(address(bank), depositAmount);
        bank.deposit(address(usdc), depositAmount);
        
        bank.withdraw(withdrawAmount);
        vm.stopPrank();
        
        assertEq(bank.getBalance(user1), depositAmount - withdrawAmount);
    }
}