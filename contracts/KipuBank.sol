// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;
/// @title Storage String
/// @author Imanol Valenzuela Eguez
contract KipuBank{
    /* ========== VARIABLES INMUTABLES Y CONSTANTES ========== */
    /**
     * @notice Límite máximo de retiro por transacción
     * @dev Establecido en el constructor como immutable para optimizar gas
     *      Valor recomendado: 0.1 ETH (100000000000000000 wei)
     */
    uint256 public immutable WITHDRAWAL_LIMIT;

    /**
     * @notice Depósito mínimo requerido para usar el banco
     * @dev Definido como constante: 0.001 ETH (1000000000000000 wei)
     */
    uint256 public constant MINIMUM_DEPOSIT =  0.001 ether;

    /**
     * @notice Dirección del propietario del contrato
     * @dev Tiene permisos administrativos como pausar el contrato
     */
    address public immutable owner;

    /* ========== VARIABLES DE ALMACENAMIENTO ========== */
    /**
     * @notice Límite total de depósitos que el banco puede aceptar
     * @dev Se establece en el constructor. Una vez alcanzado, no se permiten más depósitos
     *      Valor recomendado: 100 ETH
     */
    uint256 public bankCap;

    /**
     * @notice Total acumulado de fondos depositados actualmente en el banco
     * @dev Se actualiza en cada depósito (suma) y retiro (resta)
     */
    uint256 public totalDeposits;

    /**
     * @notice Contador global del número de depósitos realizados
     * @dev Se incrementa cada vez que un usuario deposita, independientemente del monto
     */
    uint256 public depositCount;

    /**
     * @notice Contador global del número de retiros realizados
     * @dev Se incrementa cada vez que un usuario retira fondos exitosamente
     */
    uint256 public withdrawalCount;

    /**
     * @notice Estado del circuit breaker para pausar el contrato en emergencias
     * @dev true = contrato pausado, false = contrato operativo
     */
     bool public paused;

   /* ========== MAPPINGS ========== */
    /**
     * @notice Mapeo de direcciones de usuarios a sus balances en la bóveda
     * @dev Cada dirección tiene su propia bóveda individual
     *      address => balance en wei
     */
    mapping(address => uint256) public vaults;

    /* ========== EVENTOS ========== */
    /**
     * @notice Se emite cuando un usuario deposita fondos exitosamente
     * @param user Dirección del usuario que realizó el depósito
     * @param amount Cantidad depositada en wei
     * @param newBalance Nuevo balance total del usuario en su bóveda
     */
    event Deposit(address indexed user, uint256 amount, uint256 newBalance);

    /**
     * @notice Se emite cuando un usuario retira fondos exitosamente
     * @param user Dirección del usuario que realizó el retiro
     * @param amount Cantidad retirada en wei
     * @param newBalance Nuevo balance restante del usuario en su bóveda
     */
    event Withdrawal(address indexed user, uint256 amount, uint256 newBalance);

    /**
     * @notice Se emite cuando el contrato es pausado
     * @param by Dirección que pausó el contrato
     */
    event Paused(address indexed by);
    
    /**
     * @notice Se emite cuando el contrato es despausado
     * @param by Dirección que despausó el contrato
     */
    event Unpaused(address indexed by);

    /* ========== ERRORES PERSONALIZADOS ========== */
    /**
     * @notice Error cuando el monto depositado es menor al mínimo permitido
     * @dev Se lanza si msg.value < MINIMUM_DEPOSIT
     */
    error DepositTooSmall();
    
    /**
     * @notice Error cuando el depósito excedería el límite total del banco
     * @dev Se lanza si totalDeposits + msg.value > bankCap
     */
    error BankCapExceeded();
    
    /**
     * @notice Error cuando el usuario no tiene fondos suficientes para retirar
     * @dev Se lanza si vaults[msg.sender] < amount solicitado
     */
    error InsufficientBalance();
    
    /**
     * @notice Error cuando el retiro solicitado excede el límite por transacción
     * @dev Se lanza si amount > WITHDRAWAL_LIMIT
     */
    error WithdrawalLimitExceeded();
    
    /**
     * @notice Error cuando la transferencia de ETH falla
     * @dev Se lanza si call{value}() retorna false
     */
    error TransferFailed();
    
    /**
     * @notice Error cuando se intenta retirar cero o un monto inválido
     * @dev Se lanza si amount == 0
     */
    error InvalidWithdrawalAmount();
    
    /**
     * @notice Error cuando el contrato está pausado
     * @dev Se lanza si se intenta operar mientras paused == true
     */
    error ContractPaused();
    
    /**
     * @notice Error cuando alguien que no es el owner intenta ejecutar funciones administrativas
     * @dev Se lanza si msg.sender != owner
     */
    error OnlyOwner();
    
    /**
     * @notice Error cuando se intenta depositar 0 ETH
     * @dev Se lanza si msg.value == 0
     */
    error ZeroDeposit();

    /* ========== CONSTRUCTOR ========== */
    /**
     * @notice Inicializa el contrato KipuBank con parámetros configurables
     * @param _bankCap Límite total de depósitos que el banco puede aceptar (en wei)
     * @param _withdrawalLimit Límite máximo de retiro por transacción (en wei)
     * @dev Ejemplo de despliegue:
     *      - _bankCap: 100 ether (100000000000000000000)
     *      - _withdrawalLimit: 0.1 ether (100000000000000000)
     *      El deployer se convierte automáticamente en el owner
     */
    constructor(uint256 _bankCap, uint256 _withdrawalLimit){
        bankCap = _bankCap;
        WITHDRAWAL_LIMIT = _withdrawalLimit;
        owner = msg.sender;
        paused = false;
    }

    /* ========== MODIFICADORES ========== */

    /**
     * @notice Verifica que el monto sea válido (mayor a cero)
     * @param amount Monto a validar en wei
     * @dev Previene operaciones con montos cero que no tendrían sentido
     */
    modifier validAmount(uint256 amount){
        if (amount == 0) revert InvalidWithdrawalAmount();
        _;
    }

    /**
     * @notice Verifica que el contrato no esté pausado
     * @dev Implementa el patrón circuit breaker para emergencias
     */
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }
    
    /**
     * @notice Verifica que el caller sea el owner del contrato
     * @dev Control de acceso para funciones administrativas
     */
    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    /* ========== FUNCIONES EXTERNAS PAYABLE ========== */
    /**
     * @notice Permite a los usuarios depositar ETH en su bóveda personal
     * @dev Implementa el patrón checks-effects-interactions:
     *      1. CHECKS: Valida que no esté pausado, monto mínimo y límite del banco
     *      2. EFFECTS: Actualiza estado (vaults, totalDeposits, depositCount)
     *      3. INTERACTIONS: Emite evento
     * 
     * Requisitos:
     * - El contrato no debe estar pausado
     * - msg.value debe ser > 0
     * - msg.value debe ser >= MINIMUM_DEPOSIT (0.001 ETH)
     * - El depósito no debe hacer que totalDeposits exceda bankCap
     * 
     * Emite un evento {Deposit}
     * 
     * Ejemplo de uso:
     * kipuBank.deposit{value: 0.5 ether}();
     */
    function deposit() external payable {
        // CHECKS: Validaciones de negocio
        if (msg.value < MINIMUM_DEPOSIT) revert DepositTooSmall();
        if (totalDeposits + msg.value > bankCap) revert BankCapExceeded();

        // EFFECTS: Actualización de estado (previene reentrancy)
        vaults[msg.sender] += msg.value;
        totalDeposits += msg.value;
        depositCount++;

        // INTERACTIONS: Emisión de evento (última acción)
        emit Deposit(msg.sender, msg.value, vaults[msg.sender]);
    }

    /* ========== FUNCIONES EXTERNAS ========== */
    
    /**
     * @notice Permite a los usuarios retirar ETH de su bóveda personal
     * @param amount Cantidad a retirar en wei
     * @dev Implementa checks-effects-interactions y protección contra reentrancy:
     *      1. CHECKS: Valida que no esté pausado, monto, balance y límite de retiro
     *      2. EFFECTS: Actualiza estado antes de transferir
     *      3. INTERACTIONS: Transfiere ETH usando call (seguro)
     * 
     * Requisitos:
     * - El contrato no debe estar pausado
     * - amount debe ser > 0 (validado por modificador)
     * - Usuario debe tener balance suficiente en su bóveda
     * - amount no debe exceder WITHDRAWAL_LIMIT
     * 
     * Emite un evento {Withdrawal}
     * 
     * @custom:security Actualiza el estado antes de la transferencia para prevenir reentrancy
     * 
     * Ejemplo de uso:
     * kipuBank.withdraw(0.05 ether);
     */
    function withdraw(uint256 amount) external validAmount(amount){
        // CHECKS: Validaciones de seguridad
        if (vaults[msg.sender] < amount) revert InsufficientBalance();
        if(amount > WITHDRAWAL_LIMIT) revert WithdrawalLimitExceeded();

        // EFFECTS: Actualización de estado antes de transferencia (anti-reentrancy)
        vaults[msg.sender] -= amount;
        totalDeposits -= amount;
        
        // INTERACTIONS: Transferencia externa al final
        _sendEther(msg.sender, amount);
        withdrawalCount++;

        // Emisión de evento después de transferencia exitosa
        emit Withdrawal(msg.sender, amount, vaults[msg.sender]);
    }

    /**
     * @notice Permite al usuario retirar todo su balance disponible
     * @dev Alternativa conveniente a withdraw(amount) que previene errores de cálculo
     *      Respeta el límite de retiro por transacción
     * 
     * Requisitos:
     * - El contrato no debe estar pausado
     * - El usuario debe tener balance > 0
     * 
     * Emite un evento {Withdrawal}
     * 
     * Nota: Si el balance es mayor al WITHDRAWAL_LIMIT, solo retira hasta el límite
     */
    function withdrawAll() external whenNotPaused {
        uint256 userBalance = vaults[msg.sender];
        
        // CHECKS: Validar que hay fondos para retirar
        if (userBalance == 0) revert InsufficientBalance();
        
        // Determinar el monto a retirar (el menor entre balance y límite)
        uint256 amountToWithdraw = userBalance > WITHDRAWAL_LIMIT 
            ? WITHDRAWAL_LIMIT 
            : userBalance;
        
        // EFFECTS: Actualización de estado antes de transferencia
        vaults[msg.sender] -= amountToWithdraw;
        totalDeposits -= amountToWithdraw;
        withdrawalCount++;
        
        // INTERACTIONS: Transferencia externa
        _sendEther(msg.sender, amountToWithdraw);
        
        emit Withdrawal(msg.sender, amountToWithdraw, vaults[msg.sender]);
    }
    
    /**
     * @notice Pausa el contrato en caso de emergencia (circuit breaker)
     * @dev Solo puede ser ejecutado por el owner
     *      Previene depósitos y retiros mientras está pausado
     * 
     * Emite un evento {Paused}
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }
    
    /**
     * @notice Despausa el contrato y reanuda operaciones normales
     * @dev Solo puede ser ejecutado por el owner
     * 
     * Emite un evento {Unpaused}
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }
    
    /* ========== FUNCIONES DE VISTA (VIEW) ========== */
    
    /**
     * @notice Obtiene el balance de una dirección específica en su bóveda
     * @param user Dirección del usuario a consultar
     * @return Balance del usuario en wei
     * @dev Función pública de solo lectura, no modifica el estado
     * 
     * Ejemplo de uso:
     * uint256 myBalance = kipuBank.getBalance(msg.sender);
     */
    function getBalance(address user) external view returns (uint256){
        return vaults[user];
    }

    /**
     * @notice Obtiene el balance del caller (quien llama la función)
     * @return Balance del msg.sender en wei
     * @dev Función conveniente para que usuarios consulten su propio balance
     */
    function getMyBalance() external view returns (uint256) {
        return vaults[msg.sender];
    }
    
    /**
     * @notice Obtiene estadísticas generales del banco
     * @return _totalDeposits Total de fondos depositados actualmente en el banco
     * @return _depositCount Número acumulado de operaciones de depósito
     * @return _withdrawalCount Número acumulado de operaciones de retiro
     * @return _availableCapacity Capacidad restante del banco (bankCap - totalDeposits)
     * @dev Útil para dashboards y monitoreo del estado del banco
     * 
     * Ejemplo de uso:
     * (uint256 total, uint256 deposits, uint256 withdrawals, uint256 available) = kipuBank.getBankStats();
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
     * @notice Verifica si el contrato está actualmente pausado
     * @return true si está pausado, false si está operativo
     */
    function isPaused() external view returns (bool) {
        return paused;
    }
    
    /**
     * @notice Calcula cuánto puede retirar un usuario en la próxima transacción
     * @param user Dirección del usuario a consultar
     * @return Monto máximo que puede retirar (el menor entre su balance y WITHDRAWAL_LIMIT)
     */
    function getMaxWithdrawal(address user) external view returns (uint256) {
        uint256 userBalance = vaults[user];
        return userBalance > WITHDRAWAL_LIMIT ? WITHDRAWAL_LIMIT : userBalance;
    }
    
    /* ========== FUNCIONES PRIVADAS ========== */
    
    /**
     * @notice Envía ETH de forma segura usando call
     * @param to Dirección destinataria
     * @param amount Cantidad a enviar en wei
     * @dev Usa call en lugar de transfer/send por las siguientes razones:
     *      - transfer y send tienen un límite fijo de 2300 gas
     *      - call reenvía todo el gas disponible
     *      - call es más compatible con contratos inteligentes como destinatarios
     * 
     * @custom:security Revierte si la transferencia falla
     * @custom:security Solo llamada internamente después de actualizar el estado
     * @custom:security Visibilidad private asegura que no puede ser llamada externamente
     */
    function _sendEther(address to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }
}