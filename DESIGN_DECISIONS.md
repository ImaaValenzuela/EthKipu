# 📐 Decisiones de Diseño - KipuBank V2

## Documento de Arquitectura y Justificación Técnica

Este documento explica las decisiones clave de diseño tomadas para evolucionar KipuBank V1 a V2, las razones técnicas detrás de cada elección y cómo cada mejora resuelve limitaciones específicas del contrato original.

---

## 🎯 Limitaciones Identificadas en V1

### 1. **Moneda Única (Solo ETH)**
**Limitación**: Los usuarios solo podían depositar ETH nativo.

**Impacto**:
- Falta de diversificación
- No aprovecha el ecosistema DeFi
- Límite artificial de casos de uso

**Solución V2**: Sistema multi-token con soporte para ETH y ERC20

---

### 2. **Límites en Unidades Nativas**
**Limitación**: Los límites (bank cap, withdrawal limit) estaban en ETH.

**Problema**:
```solidity
// V1: bankCap = 100 ETH
// Si ETH = $1,000 → Cap = $100,000
// Si ETH = $4,000 → Cap = $400,000
// ❌ El valor real del banco fluctúa con el precio de ETH
```

**Solución V2**: Límites en USD usando oráculos de Chainlink

---

### 3. **Sin Control de Acceso Granular**
**Limitación**: Solo owner/no-owner (binario).

**Problema**:
- No se puede delegar responsabilidades
- Un solo punto de fallo
- No escalable para equipos

**Solución V2**: Sistema de roles con OpenZeppelin AccessControl

---

### 4. **Contabilidad Simple**
**Limitación**: No había forma de comparar valores entre diferentes activos.

**Problema**:
- Imposible implementar límites globales
- No se puede calcular valor total del banco
- Difícil para usuarios comparar posiciones

**Solución V2**: Contabilidad normalizada en USD (6 decimales)

---

## 🏗️ Arquitectura de Soluciones

### 1. Sistema Multi-Token

#### Decisión: Usar `address(0)` para ETH

```solidity
address public constant NATIVE_TOKEN = address(0);
```

**Razones**:
1. **Convención estándar**: Usado por Uniswap, Aave, etc.
2. **Gas efficiency**: No necesita wrapping a WETH
3. **UX simple**: Los usuarios pueden enviar ETH directamente

**Alternativa considerada**: Usar WETH
- ❌ Requiere paso adicional de wrap
- ❌ Más gas
- ✅ Más composable con otros protocolos (no elegida por simplificación educativa)

#### Estructura de Almacenamiento

```solidity
// Multi-dimensional mapping
mapping(address => mapping(address => uint256)) public vaults;
//          user          token         balance
```

**Ventajas**:
- O(1) acceso a cualquier balance
- Sin límite de tokens por usuario
- Gas predecible

**Costo**: ~20k gas por nuevo slot

---

### 2. Integración con Chainlink Oracles

#### Decisión: Price Feeds en lugar de API calls

```solidity
AggregatorV3Interface public immutable ethUsdPriceFeed;
```

**Razones**:
1. **Descentralización**: No depende de servidores centralizados
2. **Confiabilidad**: Network de nodos distribuidos
3. **Actualización**: Precios actualizados cada ~1 hora
4. **Seguridad**: Feeds auditados y battle-tested

**Implementación de validación**:

```solidity
function _getPrice(address token) internal view returns (uint256) {
    (, int256 price, , uint256 updatedAt, ) = priceFeed.latestRoundData();
    
    if (price <= 0) revert InvalidPrice();  // Protección contra precios negativos/cero
    if (updatedAt == 0) revert StalePrice();  // Precio nunca actualizado
    if (block.timestamp - updatedAt > 3600) revert StalePrice();  // Precio obsoleto (>1h)

    return uint256(price);
}
```

**Trade-offs**:
- ✅ Seguro y descentralizado
- ✅ Costos predecibles
- ⚠️ Ligero retraso vs precios spot
- ⚠️ Dependencia de infraestructura Chainlink

---

### 3. Normalización de Decimales

#### Decisión: 6 Decimales para Contabilidad Interna

```solidity
uint8 public constant ACCOUNTING_DECIMALS = 6;
```

**Razones**:
1. **Estándar USDC/USDT**: Los stablecoins más usados tienen 6 decimales
2. **Precisión adecuada**: $0.000001 USD es suficiente granularidad
3. **Gas eficiente**: Números más pequeños → menos gas en operaciones

**Ejemplo de Conversión**:

```solidity
// ETH (18 decimals) → USD (6 decimals)
// User deposits: 1 ETH = 1_000_000_000_000_000_000 wei
// ETH price: $2,000 = 200_000_000_000 (8 decimals from Chainlink)

uint256 usdValue = (amount * price * 10^6) / (10^18 * 10^8)
                 = (1e18 * 2e11 * 1e6) / (1e18 * 1e8)
                 = 2_000_000_000  // $2,000.000000
```

**Ventajas**:
- Consistencia en toda la contabilidad
- Comparación directa entre tokens
- Simplifica cálculos de límites

**Desventajas mitigadas**:
- Pérdida mínima de precisión en conversiones (< 0.0001%)
- Complejidad de conversión manejada internamente

---

### 4. Control de Acceso con OpenZeppelin

#### Decisión: AccessControl sobre Ownable

**Comparación**:

| Aspecto | Ownable (V1) | AccessControl (V2) |
|---------|--------------|-------------------|
| Roles | 1 (owner) | Múltiples | 
| Granularidad | Baja | Alta |
| Delegación | No | Sí |
| Revocación | Solo transferencia | Por rol |
| Gas deployment | ~50k menos | Actual |
| Flexibilidad | Limitada | Total |

**Roles Implementados**:

```solidity
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
```

**Justificación de cada rol**:

1. **DEFAULT_ADMIN_ROLE**:
   - Gestión de roles
   - Control total del sistema
   - Solo para founder/DAO

2. **ADMIN_ROLE**:
   - Agregar/remover tokens
   - Configuración de price feeds
   - Para equipo técnico senior

3. **OPERATOR_ROLE**:
   - Pausar/despausar en emergencias
   - Para equipo de operaciones 24/7
   - Respuesta rápida a incidentes

**Ejemplo de delegación**:

```solidity
// Founder otorga roles al equipo
grantRole(ADMIN_ROLE, techLeadAddress);
grantRole(OPERATOR_ROLE, securityTeamAddress);
grantRole(OPERATOR_ROLE, devOpsAddress);

// Ahora múltiples personas pueden responder a emergencias
```

---

### 5. Seguridad con OpenZeppelin

#### Decisión: Usar contratos auditados sobre implementación custom

**Implementaciones usadas**:

##### A. ReentrancyGuard

```solidity
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

function withdraw(...) external nonReentrant {
    // Protección automática contra reentrancy
}
```

**Ventajas sobre implementación manual**:
- ✅ Auditado por expertos
- ✅ Battle-tested en miles de contratos
- ✅ Gas optimizado
- ✅ Mantenido por la comunidad

**Costo**: ~2,400 gas extra por función protegida

##### B. Pausable

```solidity
import "@openzeppelin/contracts/utils/Pausable.sol";

function deposit(...) external whenNotPaused {
    // Se bloquea automáticamente si paused == true
}
```

**Ventajas**:
- Circuit breaker integrado
- Eventos estandarizados
- Patrón probado

##### C. SafeERC20

```solidity
using SafeERC20 for IERC20;

IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
```

**Protección contra**:
- Tokens que no retornan bool
- Tokens que retornan false sin revertir
- Race conditions en approvals

**Ejemplo de token problemático**:

```solidity
// Token mal implementado
function transfer(address to, uint256 amount) external {
    // No retorna nada ❌
}

// SafeERC20 maneja esto correctamente ✅
```

---

### 6. Arquitectura de Conversión de Precios

#### Sistema de Conversión Bidireccional

**Token → USD**:

```solidity
function _convertToUsd(address token, uint256 amount) internal view returns (uint256) {
    uint256 price = _getPrice(token);  // Precio con 8 decimals
    uint8 decimals = tokenDecimals[token];  // Decimals del token
    
    // Formula: (amount * price * 10^ACCOUNTING_DECIMALS) / (10^decimals * 10^PRICE_FEED_DECIMALS)
    uint256 numerator = amount * price * (10 ** ACCOUNTING_DECIMALS);
    uint256 denominator = (10 ** decimals) * (10 ** PRICE_FEED_DECIMALS);
    
    return numerator / denominator;
}
```

**Casos de prueba**:

| Token | Amount | Decimals | Price (8 dec) | USD Result (6 dec) |
|-------|--------|----------|---------------|-------------------|
| ETH | 1e18 | 18 | 200000000000 ($2k) | 2000000000 |
| LINK | 15e18 | 18 | 1500000000 ($15) | 225000000 |
| WBTC | 1e8 | 8 | 4000000000000 ($40k) | 40000000000 |
| USDC | 1000e6 | 6 | 100000000 ($1) | 1000000000 |

**USD → Token**:

```solidity
function _convertFromUsd(address token, uint256 amountUsd) internal view returns (uint256) {
    uint256 price = _getPrice(token);
    uint8 decimals = tokenDecimals[token];
    
    // Formula: (amountUsd * 10^decimals * 10^PRICE_FEED_DECIMALS) / (price * 10^ACCOUNTING_DECIMALS)
    uint256 numerator = amountUsd * (10 ** decimals) * (10 ** PRICE_FEED_DECIMALS);
    uint256 denominator = price * (10 ** ACCOUNTING_DECIMALS);
    
    return numerator / denominator;
}
```

**Precisión**:
- Error máximo: < 0.01% debido a redondeo entero
- Aceptable para aplicación financiera
- Puede mejorarse con aritmética de punto fijo (futuro)

---

## 🎨 Patrones de Diseño Implementados

### 1. Checks-Effects-Interactions

**Aplicado consistentemente en todas las funciones críticas**:

```solidity
function deposit(address token, uint256 amount) external {
    // ✅ CHECKS
    if (amount == 0) revert InvalidAmount();
    if (!isTokenSupported[token]) revert TokenNotSupported();
    
    uint256 amountUsd = _convertToUsd(token, amount);
    if (amountUsd < MINIMUM_DEPOSIT_USD) revert DepositTooSmall();
    if (totalDepositsUsd + amountUsd > bankCapUsd) revert BankCapExceeded();
    
    // ✅ EFFECTS
    vaults[msg.sender][token] += amount;
    totalDepositsUsd += amountUsd;
    depositCount++;
    
    // ✅ INTERACTIONS
    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    emit Deposit(msg.sender, token, amount, amountUsd);
}
```

### 2. Pull over Push

**Retiros son "pull" (usuario inicia)**:

```solidity
// ✅ Usuario retira (pull)
function withdraw(address token, uint256 amount) external {
    // Usuario controla cuándo recibe fondos
}

// ❌ NO implementado: push automático
// function distributeRewards() external {
//     for (users) { user.transfer(reward); }  // Peligroso
// }
```

**Razones**:
- Evita DoS por gas limit
- Usuario controla el timing
- No hay riesgo de reentrancy en loops

### 3. Factory Pattern (Implícito)

**Tokens se agregan dinámicamente**:

```solidity
function addToken(address token, address priceFeed) external {
    _addToken(token, decimals, priceFeed);
    // No necesita redeployment del contrato
}
```

### 4. Guard Check Pattern

**Modificadores como guards**:

```solidity
modifier nonZeroAmount(uint256 amount) {
    if (amount == 0) revert InvalidAmount();
    _;
}

modifier whenNotPaused() {
    if (paused) revert ContractPaused();
    _;
}

// Composición
function withdraw(...) external whenNotPaused nonReentrant nonZeroAmount(amount) {
    // Múltiples validaciones antes de ejecutar
}
```

---

## 💰 Optimizaciones de Gas

### 1. Variables Inmutables

```solidity
// V1: Variable de storage (costoso)
uint256 public bankCap;  // SLOAD: ~2,100 gas

// V2: Inmutable (barato)
uint256 public immutable bankCapUsd;  // Directo del bytecode: ~3 gas
```

**Ahorro**: ~2,097 gas por lectura

### 2. Constantes

```solidity
uint8 public constant ACCOUNTING_DECIMALS = 6;
// No ocupa storage slot
// Compilador sustituye directamente en el código
```

### 3. Packing de Variables

```solidity
// Evitamos esto (2 slots):
bool public paused;    // slot 0
bool private locked;   // slot 1

// En su lugar (1 slot si se pudiera):
// OpenZeppelin ya optimiza esto internamente
```

### 4. Eventos en lugar de Storage

```solidity
// ❌ Costoso
mapping(uint => DepositInfo) public deposits;

// ✅ Económico
event Deposit(...);  // ~375 gas por log
// Datos recuperables off-chain via eventos
```

### 5. Custom Errors

```solidity
// ❌ V1: String errors (~50 gas por carácter)
require(amount > 0, "Amount must be greater than zero");

// ✅ V2: Custom errors (~50 gas total)
error InvalidAmount();
if (amount == 0) revert InvalidAmount();
```

**Ahorro**: ~2,000-3,000 gas por revert

---

## 📊 Comparación de Costos de Gas

### Deployment

| Contrato | Gas | USD (@25 gwei, ETH=$2k) |
|----------|-----|-------------------------|
| V1 | ~1.2M | ~$60 |
| V2 | ~3.5M | ~$175 |

**Aumento justificado por**:
- OpenZeppelin libraries
- Sistema multi-token
- Oracles integration
- Roles complexity

### Operaciones

| Operación | V1 | V2 | Diferencia |
|-----------|----|----|------------|
| Deposit ETH | ~50k | ~65k | +15k |
| Withdraw ETH | ~45k | ~55k | +10k |
| Deposit ERC20 | N/A | ~80k | New |
| Get Balance | ~2.5k | ~3k | +0.5k |

**Trade-off aceptable**: Más funcionalidad justifica aumento de gas.


---

## 🔄 Proceso de Upgrade (Futuro)

### Decisión: No Upgradeable (Por ahora)

**Razones**:
1. **Simplicidad**: Más fácil de auditar
2. **Inmutabilidad**: Los usuarios saben que no cambiará
3. **Gas**: Sin proxy overhead
4. **Educativo**: Más claro para aprendizaje

**Alternativa**: Proxy Pattern (UUPS o Transparent)

Si se necesitara upgradeability:

```solidity
// Usar OpenZeppelin Upgradeable
import "@openzeppelin/contracts-upgradeable/...";

contract KipuBankV2 is 
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable 
{
    function initialize(...) public initializer {
        // Constructor replacement
    }
}
```

---

## 📚 Referencias

### Inspiración de Protocolos

- **Aave**: Sistema de depósito multi-token
- **Compound**: Contabilidad normalizada
- **Uniswap**: address(0) para ETH nativo
- **MakerDAO**: Oracle integration

### Estándares Seguidos

- **EIP-20**: Token standard
- **EIP-165**: Interface detection
- **EIP-2612**: Permit pattern (futuro)

