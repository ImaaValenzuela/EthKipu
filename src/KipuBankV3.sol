// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title KipuBankV3
 * @author ImaaValenzuela
 * @notice Sistema bancario DeFi con integración a Uniswap V2 para swaps automáticos a USDC
 * @dev Características principales:
 *      - Acepta cualquier token con par en Uniswap V2
 *      - Swap automático a USDC para contabilidad unificada
 *      - Control de acceso basado en roles
 *      - Límite de banco (bankCap) en USDC
 *      - Pausabilidad y protección contra reentrancy
 * 
 * Flujo de depósito:
 * 1. Usuario deposita Token X
 * 2. Contrato verifica si Token X == USDC
 * 3. Si no es USDC, hace swap Token X → USDC via Uniswap V2
 * 4. Acredita USDC al balance del usuario
 * 5. Verifica que no se exceda bankCap
 * 
 * Arquitectura:
 * - Todos los balances internos se manejan en USDC (6 decimales)
 * - NATIVE_TOKEN (address(0)) representa ETH
 * - WETH se usa para swaps de ETH en Uniswap
 */
contract KipuBankV3 is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* ========== INTERFACES ========== */

    /// @notice Router de Uniswap V2 para realizar swaps
    IUniswapV2Router02 public immutable uniswapRouter;
    
    /// @notice Token WETH (Wrapped ETH)
    address public immutable WETH;
    
    /// @notice Token USDC - moneda base del sistema
    address public immutable USDC;

    /* ========== ROLES ========== */

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /* ========== CONSTANTES ========== */

    /// @notice Dirección especial para ETH nativo
    address public constant NATIVE_TOKEN = address(0);
    
    /// @notice Depósito mínimo en USDC (0.10 USD con 6 decimales)
    uint256 public constant MINIMUM_DEPOSIT = 100000; // 0.1 USDC
    
    /// @notice Slippage máximo permitido en swaps (5% = 500 basis points)
    uint256 public constant MAX_SLIPPAGE = 500; // 5%
    uint256 public constant SLIPPAGE_DENOMINATOR = 10000;

    /* ========== VARIABLES INMUTABLES ========== */

    /// @notice Límite máximo del banco en USDC
    uint256 public immutable bankCap;
    
    /// @notice Límite de retiro por transacción en USDC
    uint256 public immutable withdrawalLimit;

    /* ========== VARIABLES DE ESTADO ========== */

    /// @notice Total depositado en el banco (en USDC)
    uint256 public totalDeposits;
    
    /// @notice Contador de depósitos
    uint256 public depositCount;
    
    /// @notice Contador de retiros
    uint256 public withdrawalCount;
    
    /// @notice Slippage configurable por el admin (en basis points)
    uint256 public slippageTolerance;

    /* ========== MAPPINGS ========== */

    /// @notice Balance de cada usuario en USDC: user => amount
    mapping(address => uint256) public balances;
    
    /// @notice Tokens permitidos para depósito: token => isAllowed
    mapping(address => bool) public allowedTokens;
    
    /// @notice Path óptimo para swap de cada token: token => path[]
    /// @dev Si está vacío, se usa path directo [token, USDC]
    mapping(address => address[]) public swapPaths;

    /* ========== EVENTOS ========== */

    /**
     * @notice Emitido cuando un usuario deposita y recibe USDC
     * @param user Dirección del usuario
     * @param tokenIn Token depositado
     * @param amountIn Cantidad depositada
     * @param amountUsdc USDC recibido después del swap
     */
    event Deposit(
        address indexed user,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountUsdc
    );

    /**
     * @notice Emitido cuando se realiza un swap
     * @param tokenIn Token de entrada
     * @param tokenOut Token de salida (siempre USDC)
     * @param amountIn Cantidad de entrada
     * @param amountOut Cantidad de salida
     */
    event Swap(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @notice Emitido cuando un usuario retira USDC
     * @param user Dirección del usuario
     * @param amount Cantidad retirada
     */
    event Withdrawal(address indexed user, uint256 amount);

    /**
     * @notice Emitido cuando se permite un nuevo token
     * @param token Dirección del token
     * @param path Path de swap configurado
     */
    event TokenAllowed(address indexed token, address[] path);

    /**
     * @notice Emitido cuando se actualiza el slippage tolerance
     * @param oldSlippage Slippage anterior
     * @param newSlippage Nuevo slippage
     */
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);

    /* ========== ERRORES PERSONALIZADOS ========== */

    error InvalidAmount();
    error InvalidAddress();
    error TokenNotAllowed();
    error BankCapExceeded();
    error InsufficientBalance();
    error WithdrawalLimitExceeded();
    error TransferFailed();
    error SwapFailed();
    error InvalidSlippage();
    error InvalidPath();
    error DepositTooSmall();

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Inicializa KipuBankV3
     * @param _uniswapRouter Dirección del router Uniswap V2
     * @param _usdc Dirección del token USDC
     * @param _bankCap Límite máximo en USDC
     * @param _withdrawalLimit Límite de retiro en USDC
     * 
     * Ejemplo Sepolia:
     * _uniswapRouter: 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008 (Uniswap V2 Router)
     * _usdc: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238
     * _bankCap: 100000000000 (100,000 USDC)
     * _withdrawalLimit: 10000000000 (10,000 USDC)
     */
    constructor(
        address _uniswapRouter,
        address _usdc,
        uint256 _bankCap,
        uint256 _withdrawalLimit
    ) {
        if (_uniswapRouter == address(0)) revert InvalidAddress();
        if (_usdc == address(0)) revert InvalidAddress();
        if (_bankCap == 0) revert InvalidAmount();
        if (_withdrawalLimit == 0) revert InvalidAmount();
        if (_withdrawalLimit > _bankCap) revert WithdrawalLimitExceeded();

        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        WETH = uniswapRouter.WETH();
        USDC = _usdc;
        bankCap = _bankCap;
        withdrawalLimit = _withdrawalLimit;
        slippageTolerance = 300; // 3% por defecto

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);

        // Permitir USDC y ETH por defecto
        allowedTokens[USDC] = true;
        allowedTokens[NATIVE_TOKEN] = true;
    }

    /* ========== FUNCIONES ADMINISTRATIVAS ========== */

    /**
     * @notice Permite un nuevo token para depósitos
     * @param token Dirección del token
     * @param path Path de swap (vacío para path directo)
     * @dev Solo ADMIN_ROLE. Path debe terminar en USDC
     */
    function allowToken(
        address token,
        address[] calldata path
    ) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert InvalidAddress();
        if (token == USDC) revert InvalidAddress(); // USDC ya permitido
        
        // Validar path si se proporciona
        if (path.length > 0) {
            if (path[0] != token) revert InvalidPath();
            if (path[path.length - 1] != USDC) revert InvalidPath();
            swapPaths[token] = path;
        }
        
        allowedTokens[token] = true;
        emit TokenAllowed(token, path);
    }

    /**
     * @notice Actualiza el slippage tolerance
     * @param newSlippage Nuevo slippage en basis points
     * @dev Solo ADMIN_ROLE. Máximo 5%
     */
    function updateSlippage(uint256 newSlippage) external onlyRole(ADMIN_ROLE) {
        if (newSlippage > MAX_SLIPPAGE) revert InvalidSlippage();
        
        uint256 oldSlippage = slippageTolerance;
        slippageTolerance = newSlippage;
        
        emit SlippageUpdated(oldSlippage, newSlippage);
    }

    /**
     * @notice Pausa el contrato
     * @dev Solo OPERATOR_ROLE
     */
    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }

    /**
     * @notice Despausa el contrato
     * @dev Solo OPERATOR_ROLEf
     */
    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }

    /* ========== FUNCIONES EXTERNAS PAYABLE ========== */

    /**
     * @notice Deposita ETH nativo
     * @dev ETH se convierte a WETH y luego se swapea a USDC
     */
    function depositNative() external payable whenNotPaused nonReentrant {
        if (msg.value == 0) revert InvalidAmount();
        
        // Swap ETH → USDC via Uniswap
        uint256 usdcReceived = _swapNativeToUsdc(msg.value);
        
        // Validar y acreditar
        _processDeposit(msg.sender, NATIVE_TOKEN, msg.value, usdcReceived);
    }

    /* ========== FUNCIONES EXTERNAS ========== */

    /**
     * @notice Deposita tokens ERC20
     * @param token Dirección del token
     * @param amount Cantidad a depositar
     * @dev Si token != USDC, se hace swap automático
     */
    function deposit(
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (token == NATIVE_TOKEN) revert InvalidAddress();
        if (!allowedTokens[token]) revert TokenNotAllowed();

        // Transferir tokens del usuario al contrato
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 usdcAmount;
        
        if (token == USDC) {
            // Depósito directo de USDC
            usdcAmount = amount;
        } else {
            // Swap token → USDC
            usdcAmount = _swapTokenToUsdc(token, amount);
        }

        // Validar y acreditar
        _processDeposit(msg.sender, token, amount, usdcAmount);
    }

    /**
     * @notice Retira USDC
     * @param amount Cantidad a retirar
     */
    function withdraw(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (balances[msg.sender] < amount) revert InsufficientBalance();
        if (amount > withdrawalLimit) revert WithdrawalLimitExceeded();

        // Actualizar estado
        balances[msg.sender] -= amount;
        totalDeposits -= amount;
        withdrawalCount++;

        // Transferir USDC
        IERC20(USDC).safeTransfer(msg.sender, amount);

        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @notice Retira todo el balance disponible
     * @dev Respeta el límite de retiro
     */
    function withdrawAll() external whenNotPaused nonReentrant {
        uint256 userBalance = balances[msg.sender];
        if (userBalance == 0) revert InsufficientBalance();

        uint256 amountToWithdraw = userBalance > withdrawalLimit 
            ? withdrawalLimit 
            : userBalance;

        // Actualizar estado
        balances[msg.sender] -= amountToWithdraw;
        totalDeposits -= amountToWithdraw;
        withdrawalCount++;

        // Transferir USDC
        IERC20(USDC).safeTransfer(msg.sender, amountToWithdraw);

        emit Withdrawal(msg.sender, amountToWithdraw);
    }

    /* ========== FUNCIONES DE VISTA ========== */

    /**
     * @notice Obtiene el balance de un usuario
     * @param user Dirección del usuario
     * @return Balance en USDC
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    /**
     * @notice Obtiene estadísticas del banco
     * @return _totalDeposits Total en USDC
     * @return _depositCount Número de depósitos
     * @return _withdrawalCount Número de retiros
     * @return _availableCapacity Capacidad restante
     */
    function getBankStats() external view returns (
        uint256 _totalDeposits,
        uint256 _depositCount,
        uint256 _withdrawalCount,
        uint256 _availableCapacity
    ) {
        return (
            totalDeposits,
            depositCount,
            withdrawalCount,
            bankCap - totalDeposits
        );
    }

    /**
     * @notice Estima cuánto USDC se recibiría por un swap
     * @param tokenIn Token de entrada
     * @param amountIn Cantidad de entrada
     * @return amountOut Cantidad estimada de USDC
     */
    function estimateSwap(
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        if (tokenIn == USDC) return amountIn;
        
        address[] memory path = _getSwapPath(tokenIn);
        uint256[] memory amounts = uniswapRouter.getAmountsOut(amountIn, path);
        return amounts[amounts.length - 1];
    }

    /**
     * @notice Obtiene el path de swap configurado para un token
     * @param token Dirección del token
     * @return path Array con el path de swap
     */
    function getSwapPath(address token) external view returns (address[] memory path) {
        return _getSwapPath(token);
    }

    /**
     * @notice Verifica si un token está permitido
     * @param token Dirección del token
     * @return true si está permitido
     */
    function isTokenAllowed(address token) external view returns (bool) {
        return allowedTokens[token];
    }

    /* ========== FUNCIONES INTERNAS ========== */

    /**
     * @notice Procesa y valida un depósito
     * @param user Usuario que deposita
     * @param tokenIn Token depositado
     * @param amountIn Cantidad depositada
     * @param usdcAmount USDC recibido
     */
    function _processDeposit(
        address user,
        address tokenIn,
        uint256 amountIn,
        uint256 usdcAmount
    ) internal {
        // Validaciones
        if (usdcAmount < MINIMUM_DEPOSIT) revert DepositTooSmall();
        if (totalDeposits + usdcAmount > bankCap) revert BankCapExceeded();

        // Actualizar estado
        balances[user] += usdcAmount;
        totalDeposits += usdcAmount;
        depositCount++;

        emit Deposit(user, tokenIn, amountIn, usdcAmount);
    }

    /**
     * @notice Swap de ETH nativo a USDC
     * @param amountIn Cantidad de ETH
     * @return amountOut USDC recibido
     */
    function _swapNativeToUsdc(uint256 amountIn) internal returns (uint256 amountOut) {
        // Path: ETH → USDC (via WETH)
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;

        // Calcular mínimo con slippage
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(amountIn, path);
        uint256 amountOutMin = _applySlippage(amountsOut[1]);

        // Ejecutar swap
        uint256[] memory amounts = uniswapRouter.swapExactETHForTokens{value: amountIn}(
            amountOutMin,
            path,
            address(this),
            block.timestamp + 300 // 5 min deadline
        );

        amountOut = amounts[amounts.length - 1];
        emit Swap(NATIVE_TOKEN, USDC, amountIn, amountOut);
    }

    /**
     * @notice Swap de token ERC20 a USDC
     * @param tokenIn Token de entrada
     * @param amountIn Cantidad de entrada
     * @return amountOut USDC recibido
     */
    function _swapTokenToUsdc(
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        // Obtener path óptimo
        address[] memory path = _getSwapPath(tokenIn);

        // Aprobar router
        IERC20(tokenIn).forceApprove(address(uniswapRouter), amountIn);

        // Calcular mínimo con slippage
        uint256[] memory amountsOut = uniswapRouter.getAmountsOut(amountIn, path);
        uint256 amountOutMin = _applySlippage(amountsOut[amountsOut.length - 1]);

        // Ejecutar swap
        uint256[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp + 300
        );

        amountOut = amounts[amounts.length - 1];
        
        // Reset approval
        IERC20(tokenIn).forceApprove(address(uniswapRouter), 0);

        emit Swap(tokenIn, USDC, amountIn, amountOut);
    }

    /**
     * @notice Obtiene el path de swap para un token
     * @param token Token de entrada
     * @return path Path de swap
     */
    function _getSwapPath(address token) internal view returns (address[] memory path) {
        // Si hay path customizado, usarlo
        if (swapPaths[token].length > 0) {
            return swapPaths[token];
        }

        // Path directo: token → USDC
        path = new address[](2);
        path[0] = token;
        path[1] = USDC;
    }

    /**
     * @notice Aplica slippage tolerance a un monto
     * @param amount Monto original
     * @return Monto con slippage aplicado
     */
    function _applySlippage(uint256 amount) internal view returns (uint256) {
        return amount * (SLIPPAGE_DENOMINATOR - slippageTolerance) / SLIPPAGE_DENOMINATOR;
    }

    /* ========== FUNCIONES RECEIVE Y FALLBACK ========== */

    receive() external payable {
        if (msg.value > 0 && !paused()) {
            // Redireccionar a depositNative
            // Nota: nonReentrant se aplica en depositNative
            uint256 usdcReceived = _swapNativeToUsdc(msg.value);
            _processDeposit(msg.sender, NATIVE_TOKEN, msg.value, usdcReceived);
        }
    }

    fallback() external payable {
        if (msg.value > 0 && !paused()) {
            uint256 usdcReceived = _swapNativeToUsdc(msg.value);
            _processDeposit(msg.sender, NATIVE_TOKEN, msg.value, usdcReceived);
        }
    }
}

/* ========== INTERFACES ========== */

/**
 * @notice Interfaz del Router de Uniswap V2
 */
interface IUniswapV2Router02 {
    function WETH() external view returns (address);
    
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
    
    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);
}