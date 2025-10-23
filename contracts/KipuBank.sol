// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol"; 
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBankV2
 *  @author ImaaValenzuela
 * @notice Sistema avanzado de bóveda bancaria descentralizada multi-token con oracle de precios
 * @dev Implementa:
 *      - Soporte multi-token (ETH y ERC20)
 *      - Control de acceso basado en roles (OpenZeppelin AccessControl)
 *      - Oracle de Chainlink para conversión ETH/USD
 *      - Contabilidad interna normalizada a decimales USDC (6 decimales)
 *      - Pausabilidad con OpenZeppelin Pausable
 *      - Protección contra reentrancy con OpenZeppelin ReentrancyGuard
 *      - Límite del banco en USD
 * 
 * Arquitectura:
 * - address(0) representa depósitos en ETH nativo
 * - Todos los montos se normalizan a 6 decimales (estándar USDC) internamente
 * - Los límites se manejan en USD usando Chainlink Price Feeds
 */
contract KipuBankV2 is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* ========== ROLES ========== */

    /// @notice Rol de administrador con permisos elevados
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Rol de operador que puede pausar/despausar en emergencias
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /* ========== CONSTANTES ========== */

    /// @notice Dirección especial que representa ETH nativo
    address public constant NATIVE_TOKEN = address(0);
    
    /// @notice Decimales de referencia para contabilidad interna (USDC standard)
    uint8 public constant ACCOUNTING_DECIMALS = 6;
    
    /// @notice Depósito mínimo en USD (0.10 USD con 6 decimales)
    uint256 public constant MINIMUM_DEPOSIT_USD = 100000; // 0.1 USD
    
    /// @notice Decimales del price feed de Chainlink (generalmente 8)
    uint8 public constant PRICE_FEED_DECIMALS = 8;

    /* ========== VARIABLES INMUTABLES ========== */

    /// @notice Oracle de Chainlink para precio ETH/USD
    AggregatorV3Interface public immutable ethUsdPriceFeed;
    
    /// @notice Límite máximo del banco en USD (con ACCOUNTING_DECIMALS)
    uint256 public immutable bankCapUsd;
    
    /// @notice Límite de retiro por transacción en USD (con ACCOUNTING_DECIMALS)
    uint256 public immutable withdrawalLimitUsd;

    /* ========== VARIABLES DE ESTADO ========== */

    /// @notice Total de depósitos en el banco expresado en USD normalizado
    uint256 public totalDepositsUsd;
    
    /// @notice Contador global de operaciones de depósito
    uint256 public depositCount;
    
    /// @notice Contador global de operaciones de retiro
    uint256 public withdrawalCount;
    
    /// @notice Lista de tokens soportados por el banco
    address[] public supportedTokens;

    /* ========== MAPPINGS ========== */

    /// @notice Balance de cada usuario por token: user => token => amount (en decimales nativos del token)
    mapping(address => mapping(address => uint256)) public vaults;
    
    /// @notice Verifica si un token está soportado
    mapping(address => bool) public isTokenSupported;
    
    /// @notice Decimales de cada token soportado (0 para ETH = 18 decimales)
    mapping(address => uint8) public tokenDecimals;
    
    /// @notice Oracle de precio para cada token ERC20: token => price feed
    /// @dev ETH usa ethUsdPriceFeed directamente
    mapping(address => AggregatorV3Interface) public tokenPriceFeeds;

    /* ========== STRUCTS ========== */

    /// @notice Información de un token soportado
    struct TokenInfo {
        address tokenAddress;
        uint8 decimals;
        bool isSupported;
        address priceFeed;
    }

    /* ========== EVENTOS ========== */

    /**
     * @notice Emitido cuando un usuario deposita fondos
     * @param user Dirección del usuario
     * @param token Dirección del token (address(0) para ETH)
     * @param amount Cantidad depositada en decimales nativos del token
     * @param amountUsd Valor del depósito en USD normalizado
     */
    event Deposit(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 amountUsd
    );

    /**
     * @notice Emitido cuando un usuario retira fondos
     * @param user Dirección del usuario
     * @param token Dirección del token (address(0) para ETH)
     * @param amount Cantidad retirada en decimales nativos del token
     * @param amountUsd Valor del retiro en USD normalizado
     */
    event Withdrawal(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 amountUsd
    );

    /**
     * @notice Emitido cuando se agrega un nuevo token soportado
     * @param token Dirección del token
     * @param decimals Decimales del token
     * @param priceFeed Dirección del oracle de precio
     */
    event TokenAdded(
        address indexed token,
        uint8 decimals,
        address priceFeed
    );

    /**
     * @notice Emitido cuando se remueve un token
     * @param token Dirección del token removido
     */
    event TokenRemoved(address indexed token);

    /* ========== ERRORES PERSONALIZADOS ========== */

    error TokenNotSupported();
    error TokenAlreadySupported();
    error InvalidAmount();
    error InvalidTokenAddress();
    error InvalidPriceFeed();
    error DepositTooSmall();
    error BankCapExceeded();
    error InsufficientBalance();
    error WithdrawalLimitExceeded();
    error TransferFailed();
    error StalePrice();
    error InvalidPrice();

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Inicializa KipuBankV2
     * @param _ethUsdPriceFeed Dirección del oracle Chainlink ETH/USD
     * @param _bankCapUsd Límite del banco en USD (con 6 decimales)
     * @param _withdrawalLimitUsd Límite de retiro en USD (con 6 decimales)
     * @dev El deployer recibe DEFAULT_ADMIN_ROLE, ADMIN_ROLE y OPERATOR_ROLE
     * 
     * Ejemplo Sepolia:
     * _ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306
     * _bankCapUsd: 100000000000 (100,000 USD)
     * _withdrawalLimitUsd: 1000000000 (1,000 USD)
     */
    constructor(
        address _ethUsdPriceFeed,
        uint256 _bankCapUsd,
        uint256 _withdrawalLimitUsd
    ) {
        if (_ethUsdPriceFeed == address(0)) revert InvalidPriceFeed();
        if (_bankCapUsd == 0) revert InvalidAmount();
        if (_withdrawalLimitUsd == 0) revert InvalidAmount();
        if (_withdrawalLimitUsd > _bankCapUsd) revert WithdrawalLimitExceeded();

        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        bankCapUsd = _bankCapUsd;
        withdrawalLimitUsd = _withdrawalLimitUsd;

        // Configurar roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);

        // Agregar ETH como token soportado por defecto
        _addToken(NATIVE_TOKEN, 18, _ethUsdPriceFeed);
    }

    /* ========== FUNCIONES ADMINISTRATIVAS ========== */

    /**
     * @notice Agrega un nuevo token ERC20 soportado
     * @param token Dirección del token ERC20
     * @param priceFeed Dirección del oracle Chainlink para este token
     * @dev Solo ADMIN_ROLE puede ejecutar
     */
    function addToken(
        address token,
        address priceFeed
    ) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert InvalidTokenAddress();
        if (token == NATIVE_TOKEN) revert TokenAlreadySupported();
        if (priceFeed == address(0)) revert InvalidPriceFeed();
        if (isTokenSupported[token]) revert TokenAlreadySupported();

        // Obtener decimales del token ERC20
        uint8 decimals = IERC20Metadata(token).decimals();
        
        _addToken(token, decimals, priceFeed);
    }

    /**
     * @notice Remueve un token del sistema
     * @param token Dirección del token a remover
     * @dev No se puede remover ETH nativo. Solo ADMIN_ROLE puede ejecutar
     */
    function removeToken(address token) external onlyRole(ADMIN_ROLE) {
        if (token == NATIVE_TOKEN) revert InvalidTokenAddress();
        if (!isTokenSupported[token]) revert TokenNotSupported();

        isTokenSupported[token] = false;
        delete tokenDecimals[token];
        delete tokenPriceFeeds[token];

        // Remover de la lista
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[supportedTokens.length - 1];
                supportedTokens.pop();
                break;
            }
        }

        emit TokenRemoved(token);
    }

    /**
     * @notice Pausa todas las operaciones del contrato
     * @dev Solo OPERATOR_ROLE puede ejecutar
     */
    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }

    /**
     * @notice Despausa el contrato
     * @dev Solo OPERATOR_ROLE puede ejecutar
     */
    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }

    /* ========== FUNCIONES EXTERNAS PAYABLE ========== */

    /**
     * @notice Deposita ETH nativo en la bóveda
     * @dev Función payable que acepta ETH
     */
    function depositNative() external payable whenNotPaused nonReentrant {
        if (msg.value == 0) revert InvalidAmount();
        _deposit(NATIVE_TOKEN, msg.value);
    }

    /* ========== FUNCIONES EXTERNAS ========== */

    /**
     * @notice Deposita tokens ERC20 en la bóveda
     * @param token Dirección del token ERC20
     * @param amount Cantidad a depositar en decimales nativos del token
     * @dev Requiere aprobación previa del token
     */
    function deposit(
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (token == NATIVE_TOKEN) revert InvalidTokenAddress();
        if (amount == 0) revert InvalidAmount();
        if (!isTokenSupported[token]) revert TokenNotSupported();

        // Transferir tokens del usuario al contrato
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        _deposit(token, amount);
    }

    /**
     * @notice Retira tokens de la bóveda
     * @param token Dirección del token (address(0) para ETH)
     * @param amount Cantidad a retirar en decimales nativos del token
     */
    function withdraw(
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();
        if (!isTokenSupported[token]) revert TokenNotSupported();
        if (vaults[msg.sender][token] < amount) revert InsufficientBalance();

        // Convertir a USD para verificar límite
        uint256 amountUsd = _convertToUsd(token, amount);
        if (amountUsd > withdrawalLimitUsd) revert WithdrawalLimitExceeded();

        // Actualizar estado
        vaults[msg.sender][token] -= amount;
        totalDepositsUsd -= amountUsd;
        withdrawalCount++;

        // Transferir fondos
        if (token == NATIVE_TOKEN) {
            _sendNative(msg.sender, amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit Withdrawal(msg.sender, token, amount, amountUsd);
    }

    /**
     * @notice Retira todo el balance disponible de un token
     * @param token Dirección del token (address(0) para ETH)
     * @dev Respeta el límite de retiro en USD
     */
    function withdrawAll(address token) external whenNotPaused nonReentrant {
        if (!isTokenSupported[token]) revert TokenNotSupported();
        
        uint256 userBalance = vaults[msg.sender][token];
        if (userBalance == 0) revert InsufficientBalance();

        // Convertir balance a USD
        uint256 balanceUsd = _convertToUsd(token, userBalance);
        
        // Determinar cuánto puede retirar
        uint256 amountToWithdraw;
        uint256 amountUsd;
        
        if (balanceUsd <= withdrawalLimitUsd) {
            // Puede retirar todo
            amountToWithdraw = userBalance;
            amountUsd = balanceUsd;
        } else {
            // Solo puede retirar hasta el límite
            amountToWithdraw = _convertFromUsd(token, withdrawalLimitUsd);
            amountUsd = withdrawalLimitUsd;
        }

        // Actualizar estado
        vaults[msg.sender][token] -= amountToWithdraw;
        totalDepositsUsd -= amountUsd;
        withdrawalCount++;

        // Transferir fondos
        if (token == NATIVE_TOKEN) {
            _sendNative(msg.sender, amountToWithdraw);
        } else {
            IERC20(token).safeTransfer(msg.sender, amountToWithdraw);
        }

        emit Withdrawal(msg.sender, token, amountToWithdraw, amountUsd);
    }

    /* ========== FUNCIONES DE VISTA ========== */

    /**
     * @notice Obtiene el balance de un usuario en un token específico
     * @param user Dirección del usuario
     * @param token Dirección del token
     * @return Balance en decimales nativos del token
     */
    function getBalance(
        address user,
        address token
    ) external view returns (uint256) {
        return vaults[user][token];
    }

    /**
     * @notice Obtiene el balance de un usuario en USD
     * @param user Dirección del usuario
     * @param token Dirección del token
     * @return Balance en USD con ACCOUNTING_DECIMALS
     */
    function getBalanceInUsd(
        address user,
        address token
    ) external view returns (uint256) {
        uint256 balance = vaults[user][token];
        return _convertToUsd(token, balance);
    }

    /**
     * @notice Obtiene todos los balances de un usuario
     * @param user Dirección del usuario
     * @return tokens Array de direcciones de tokens
     * @return balances Array de balances correspondientes
     * @return balancesUsd Array de balances en USD
     */
    function getAllBalances(address user) external view returns (
        address[] memory tokens,
        uint256[] memory balances,
        uint256[] memory balancesUsd
    ) {
        uint256 length = supportedTokens.length;
        tokens = new address[](length);
        balances = new uint256[](length);
        balancesUsd = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            address token = supportedTokens[i];
            uint256 balance = vaults[user][token];
            
            tokens[i] = token;
            balances[i] = balance;
            balancesUsd[i] = _convertToUsd(token, balance);
        }

        return (tokens, balances, balancesUsd);
    }

    /**
     * @notice Obtiene estadísticas generales del banco
     * @return _totalDepositsUsd Total depositado en USD
     * @return _depositCount Número de depósitos
     * @return _withdrawalCount Número de retiros
     * @return _availableCapacityUsd Capacidad restante en USD
     */
    function getBankStats() external view returns (
        uint256 _totalDepositsUsd,
        uint256 _depositCount,
        uint256 _withdrawalCount,
        uint256 _availableCapacityUsd
    ) {
        return (
            totalDepositsUsd,
            depositCount,
            withdrawalCount,
            bankCapUsd - totalDepositsUsd
        );
    }

    /**
     * @notice Obtiene la lista de tokens soportados
     * @return Array de direcciones de tokens soportados
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    /**
     * @notice Obtiene información completa de un token
     * @param token Dirección del token
     * @return info Estructura con información del token
     */
    function getTokenInfo(address token) external view returns (TokenInfo memory info) {
        return TokenInfo({
            tokenAddress: token,
            decimals: tokenDecimals[token],
            isSupported: isTokenSupported[token],
            priceFeed: address(tokenPriceFeeds[token])
        });
    }

    /**
     * @notice Obtiene el precio actual de un token en USD
     * @param token Dirección del token
     * @return Precio en USD con PRICE_FEED_DECIMALS
     */
    function getTokenPrice(address token) external view returns (uint256) {
        return _getPrice(token);
    }

    /**
     * @notice Convierte una cantidad de token a USD
     * @param token Dirección del token
     * @param amount Cantidad en decimales nativos del token
     * @return Valor en USD con ACCOUNTING_DECIMALS
     */
    function convertToUsd(
        address token,
        uint256 amount
    ) external view returns (uint256) {
        return _convertToUsd(token, amount);
    }

    /**
     * @notice Convierte un monto en USD a cantidad de token
     * @param token Dirección del token
     * @param amountUsd Monto en USD con ACCOUNTING_DECIMALS
     * @return Cantidad en decimales nativos del token
     */
    function convertFromUsd(
        address token,
        uint256 amountUsd
    ) external view returns (uint256) {
        return _convertFromUsd(token, amountUsd);
    }

    /**
     * @notice Calcula el máximo que un usuario puede retirar
     * @param user Dirección del usuario
     * @param token Dirección del token
     * @return Cantidad máxima en decimales nativos del token
     */
    function getMaxWithdrawal(
        address user,
        address token
    ) external view returns (uint256) {
        uint256 userBalance = vaults[user][token];
        uint256 balanceUsd = _convertToUsd(token, userBalance);
        
        if (balanceUsd <= withdrawalLimitUsd) {
            return userBalance;
        } else {
            return _convertFromUsd(token, withdrawalLimitUsd);
        }
    }

    /* ========== FUNCIONES INTERNAS ========== */

    /**
     * @notice Agrega un token al sistema
     * @param token Dirección del token
     * @param decimals Decimales del token
     * @param priceFeed Dirección del oracle
     */
    function _addToken(
        address token,
        uint8 decimals,
        address priceFeed
    ) internal {
        isTokenSupported[token] = true;
        tokenDecimals[token] = decimals;
        tokenPriceFeeds[token] = AggregatorV3Interface(priceFeed);
        supportedTokens.push(token);

        emit TokenAdded(token, decimals, priceFeed);
    }

    /**
     * @notice Lógica interna de depósito
     * @param token Dirección del token
     * @param amount Cantidad en decimales nativos del token
     */
    function _deposit(address token, uint256 amount) internal {
        // Convertir a USD
        uint256 amountUsd = _convertToUsd(token, amount);
        
        // Validar monto mínimo
        if (amountUsd < MINIMUM_DEPOSIT_USD) revert DepositTooSmall();
        
        // Validar capacidad del banco
        if (totalDepositsUsd + amountUsd > bankCapUsd) revert BankCapExceeded();

        // Actualizar estado
        vaults[msg.sender][token] += amount;
        totalDepositsUsd += amountUsd;
        depositCount++;

        emit Deposit(msg.sender, token, amount, amountUsd);
    }

    /**
     * @notice Obtiene el precio de un token desde Chainlink
     * @param token Dirección del token
     * @return Precio con PRICE_FEED_DECIMALS
     */
    function _getPrice(address token) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = token == NATIVE_TOKEN 
            ? ethUsdPriceFeed 
            : tokenPriceFeeds[token];

        (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
        
        if (price <= 0) revert InvalidPrice();
        if (updatedAt == 0) revert StalePrice();
        // Chainlink heartbeat: 3600s para ETH/USD en Sepolia
        if (block.timestamp - updatedAt > 3600) revert StalePrice();

        return uint256(price);
    }

    /**
     * @notice Convierte cantidad de token a USD
     * @param token Dirección del token
     * @param amount Cantidad en decimales nativos
     * @return Valor en USD con ACCOUNTING_DECIMALS
     */
    function _convertToUsd(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        if (amount == 0) return 0;

        uint256 price = _getPrice(token);
        uint8 decimals = tokenDecimals[token];

        // Fórmula: (amount * price) / (10^decimals) / (10^PRICE_FEED_DECIMALS) * (10^ACCOUNTING_DECIMALS)
        // Simplificado: (amount * price * 10^ACCOUNTING_DECIMALS) / (10^decimals * 10^PRICE_FEED_DECIMALS)
        
        uint256 numerator = amount * price * (10 ** ACCOUNTING_DECIMALS);
        uint256 denominator = (10 ** decimals) * (10 ** PRICE_FEED_DECIMALS);
        
        return numerator / denominator;
    }

    /**
     * @notice Convierte USD a cantidad de token
     * @param token Dirección del token
     * @param amountUsd Monto en USD con ACCOUNTING_DECIMALS
     * @return Cantidad en decimales nativos del token
     */
    function _convertFromUsd(
        address token,
        uint256 amountUsd
    ) internal view returns (uint256) {
        if (amountUsd == 0) return 0;

        uint256 price = _getPrice(token);
        uint8 decimals = tokenDecimals[token];

        // Fórmula: (amountUsd * 10^decimals * 10^PRICE_FEED_DECIMALS) / (price * 10^ACCOUNTING_DECIMALS)
        
        uint256 numerator = amountUsd * (10 ** decimals) * (10 ** PRICE_FEED_DECIMALS);
        uint256 denominator = price * (10 ** ACCOUNTING_DECIMALS);
        
        return numerator / denominator;
    }

 /**
     * @notice Envía ETH nativo de forma segura
     * @param to Destinatario
     * @param amount Cantidad en wei
     */
    function _sendNative(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @dev Solución: override explícito por si AccessControl y otros generan ambigüedad
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
