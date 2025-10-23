# 🏦 KipuBank V2 - Sistema Bancario Descentralizado Multi-Token

![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-5.0-purple)
![Chainlink](https://img.shields.io/badge/Chainlink-Oracles-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Network](https://img.shields.io/badge/Network-Sepolia-orange)

## 🚀 Evolución del Proyecto

KipuBank V2 es la evolución completa del contrato original, transformándolo en un sistema bancario descentralizado de nivel producción con soporte multi-token, oráculos de precios y contabilidad avanzada.

### 🆚 V1 vs V2

| Característica | V1 | V2 |
|---------------|----|----|
| **Tokens soportados** | Solo ETH | ETH + ERC20 múltiples |
| **Control de acceso** | Owner simple | Roles (Admin, Operator) |
| **Límites** | En ETH | En USD (oracle Chainlink) |
| **Contabilidad** | Simple | Multi-token normalizada |
| **Seguridad** | Manual | OpenZeppelin (Pausable, ReentrancyGuard) |
| **Oráculos** | ❌ | ✅ Chainlink Price Feeds |
| **Decimales** | Fijos | Conversión automática |

## 📋 Descripción

KipuBank V2 es un sistema avanzado de bóvedas descentralizadas que permite:

- ✅ **Depósitos multi-token**: ETH nativo y múltiples tokens ERC20
- ✅ **Oráculos de Chainlink**: Conversión en tiempo real a USD
- ✅ **Contabilidad normalizada**: Todos los montos se contabilizan en USD (6 decimales)
- ✅ **Control de acceso por roles**: Administradores y operadores
- ✅ **Límites dinámicos**: Bank cap y límites de retiro en USD
- ✅ **Pausabilidad**: Sistema de emergencia con roles
- ✅ **Conversión de decimales**: Manejo automático de diferentes estándares
- ✅ **Seguridad robusta**: OpenZeppelin + patrones avanzados

## 🏗️ Arquitectura

### Diagrama de Componentes

```
┌─────────────────────────────────────────────────┐
│           KipuBank V2 Contract                  │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────┐      ┌──────────────┐       │
│  │ AccessControl│      │  Pausable    │       │
│  │ (Roles)      │      │  (Emergency) │       │
│  └──────────────┘      └──────────────┘       │
│                                                 │
│  ┌──────────────┐      ┌──────────────┐       │
│  │ ReentrancyG  │      │  SafeERC20   │       │
│  │ (Security)   │      │  (Transfers) │       │
│  └──────────────┘      └──────────────┘       │
│                                                 │
│  ┌─────────────────────────────────────┐      │
│  │   Chainlink Price Feeds             │      │
│  │   ETH/USD, Token/USD                │      │
│  └─────────────────────────────────────┘      │
│                                                 │
│  ┌─────────────────────────────────────┐      │
│  │   Multi-Token Vault System          │      │
│  │   address(0) = ETH                  │      │
│  │   Normalized to 6 decimals (USD)    │      │
│  └─────────────────────────────────────┘      │
└─────────────────────────────────────────────────┘
```

### Roles y Permisos

```
DEFAULT_ADMIN_ROLE (Super Admin)
├── Puede otorgar/revocar todos los roles
└── Gestión completa del sistema

ADMIN_ROLE
├── Agregar nuevos tokens ERC20
├── Remover tokens del sistema
└── Configuración de price feeds

OPERATOR_ROLE
├── Pausar contrato en emergencias
└── Despausar el contrato
```

### Flujo de Depósito

```
Usuario                  Contrato              Chainlink
  │                         │                      │
  │──deposit ETH/Token─────>│                      │
  │                         │──get price──────────>│
  │                         │<─ETH/USD price───────│
  │                         │                      │
  │                         │ Convert to USD       │
  │                         │ (normalize decimals) │
  │                         │                      │
  │                         │ Check bank cap       │
  │                         │ Update vaults        │
  │<──emit Deposit event────│                      │
```

### Contabilidad Multi-Token

**Concepto Clave**: Todos los montos se normalizan a **6 decimales** (estándar USDC) para contabilidad interna.

```solidity
// Ejemplo: Usuario deposita 1 ETH cuando ETH = $2,000
// 1. ETH tiene 18 decimales
// 2. Price feed devuelve: 200000000000 (8 decimals) = $2,000
// 3. Conversión a USD normalizado (6 decimals):
//    (1 * 10^18 * 200000000000 * 10^6) / (10^18 * 10^8) = 2000000000
//    = $2,000.00 (con 6 decimales)

// Usuario puede retirar en cualquier token soportado
// El sistema convierte USD → cantidad del token automáticamente
```

## 🔒 Seguridad

### Protecciones Implementadas

| Protección | Implementación |
|------------|----------------|
| **Reentrancy** | OpenZeppelin ReentrancyGuard |
| **Access Control** | OpenZeppelin AccessControl (3 roles) |
| **Pausabilidad** | OpenZeppelin Pausable |
| **Safe Transfers** | OpenZeppelin SafeERC20 |
| **Oracle Validation** | Verificación de precios stale/inválidos |
| **Checks-Effects-Interactions** | Patrón aplicado consistentemente |

### Validaciones de Oracle

```solidity
// El contrato valida:
✅ Precio > 0
✅ Timestamp de actualización existe
✅ Precio no más viejo de 3600 segundos (1 hora)
❌ Revierte con StalePrice si falla alguna validación
```

## 📦 Dependencias

```json
{
  "@openzeppelin/contracts": "^5.0.0",
  "@chainlink/contracts": "^1.0.0"
}
```

## 🔧 Uso del Contrato

### 1. Depositar ETH

**Via Etherscan:**

1. Ir a "Write Contract" → Conectar wallet
2. Buscar función `depositNative`
3. Ingresar monto en ETH (ej: `0.1`)
4. Click "Write"

**Ejemplo con cast:**

```bash
cast send CONTRATO_ADDRESS "depositNative()" \
  --value 0.1ether \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

### 2. Agregar Token ERC20 (Solo Admin)

**Tokens de prueba en Sepolia:**

| Token | Dirección | Price Feed |
|-------|-----------|------------|
| LINK | `0x779877A7B0D9E8603169DdbD7836e478b4624789` | `0xc59E3633BAAC79493d908e63626716e204A45EdF` |
| USDC | `0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8` | - |

```javascript
// Etherscan Write Contract
addToken(
  "0x779877A7B0D9E8603169DdbD7836e478b4624789", // LINK token
  "0xc59E3633BAAC79493d908e63626716e204A45EdF"  // LINK/USD feed
)
```

### 3. Depositar Token ERC20

**Paso 1: Aprobar**

```javascript
// En el contrato del token ERC20 → approve
approve(
  KIPUBANK_ADDRESS,
  "1000000000000000000" // 1 token (18 decimales)
)
```

**Paso 2: Depositar**

```javascript
// En KipuBankV2 → deposit
deposit(
  "0x779877A7B0D9E8603169DdbD7836e478b4624789", // token address
  "1000000000000000000" // amount
)
```

### 4. Consultar Balances

**Balance de un token específico:**

```javascript
// Read Contract
getBalance(
  "YOUR_ADDRESS",
  "0x0000000000000000000000000000000000000000" // address(0) para ETH
)
```

**Balance en USD:**

```javascript
getBalanceInUsd(
  "YOUR_ADDRESS",
  "0x0000000000000000000000000000000000000000"
)
// Retorna: balance en USD con 6 decimales
```

**Todos los balances:**

```javascript
getAllBalances("YOUR_ADDRESS")
// Retorna 3 arrays: tokens, balances, balancesUsd
```

### 5. Retirar Fondos

**Retiro específico:**

```javascript
withdraw(
  "0x0000000000000000000000000000000000000000", // ETH
  "100000000000000000" // 0.1 ETH
)
```

**Retiro total (hasta límite):**

```javascript
withdrawAll(
  "0x0000000000000000000000000000000000000000" // ETH
)
```

### 6. Gestión de Roles

**Otorgar rol de Operator:**

```javascript
// Solo DEFAULT_ADMIN_ROLE puede ejecutar
grantRole(
  "0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929", // OPERATOR_ROLE
  "0x..." // nueva dirección
)
```

**Verificar rol:**

```javascript
hasRole(
  "0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929",
  "0x..." // dirección a verificar
)
```

### 7. Pausar en Emergencia (Solo Operator)

```javascript
pause() // Pausa todas las operaciones

// Después de resolver el problema
unpause() // Reactiva el contrato
```

## 📊 Funciones de Vista Importantes

### Estadísticas del Banco

```javascript
getBankStats()
// Retorna:
// - totalDepositsUsd: Total en USD
// - depositCount: Número de depósitos
// - withdrawalCount: Número de retiros
// - availableCapacityUsd: Capacidad restante
```

### Tokens Soportados

```javascript
getSupportedTokens()
// Retorna array de direcciones
// [address(0), 0x779..., 0x94a...]

getTokenInfo("0x779877A7B0D9E8603169DdbD7836e478b4624789")
// Retorna: {
//   tokenAddress,
//   decimals,
//   isSupported,
//   priceFeed
// }
```

### Precios y Conversiones

```javascript
// Precio actual del token
getTokenPrice("0x0000000000000000000000000000000000000000")
// Retorna precio de ETH en USD (8 decimales)

// Convertir token a USD
convertToUsd(
  "0x0000000000000000000000000000000000000000",
  "1000000000000000000" // 1 ETH
)
// Retorna valor en USD (6 decimales)

// Convertir USD a token
convertFromUsd(
  "0x0000000000000000000000000000000000000000",
  "2000000000" // $2000 USD
)
// Retorna cantidad de ETH
```

### Máximo Retiro

```javascript
getMaxWithdrawal(
  "YOUR_ADDRESS",
  "0x0000000000000000000000000000000000000000"
)
// Retorna: mínimo entre balance y withdrawalLimitUsd
```


## 📈 Conversión de Decimales

### Tabla de Referencia

| Token | Decimales Nativos | Ejemplo | USD (6 dec) |
|-------|-------------------|---------|-------------|
| ETH | 18 | 1 ETH = 1e18 wei | $2,000 = 2000000000 |
| LINK | 18 | 1 LINK = 1e18 | $15 = 15000000 |
| USDC | 6 | 1 USDC = 1e6 | $1 = 1000000 |

### Fórmulas de Conversión

**Token → USD:**
```
USD = (amount * price * 10^6) / (10^tokenDecimals * 10^8)

Donde:
- amount: cantidad en decimales nativos del token
- price: precio del token en USD con 8 decimales (Chainlink)
- 10^6: decimales de contabilidad (ACCOUNTING_DECIMALS)
- 10^tokenDecimals: decimales del token
- 10^8: decimales del price feed
```

**USD → Token:**
```
amount = (amountUSD * 10^tokenDecimals * 10^8) / (price * 10^6)
```

## 🔗 Chainlink Price Feeds en Sepolia

| Par | Dirección | Decimales |
|-----|-----------|-----------|
| ETH/USD | `0x694AA1769357215DE4FAC081bf1f309aDC325306` | 8 |
| LINK/USD | `0xc59E3633BAAC79493d908e63626716e204A45EdF` | 8 |

Más feeds: [Chainlink Sepolia Feeds](https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1#sepolia-testnet)

## ⚠️ Errores Comunes

| Error | Causa | Solución |
|-------|-------|----------|
| `TokenNotSupported()` | Token no agregado al sistema | Admin debe agregar con `addToken()` |
| `DepositTooSmall()` | Depósito < $0.10 USD | Depositar mínimo $0.10 |
| `BankCapExceeded()` | Banco alcanzó límite en USD | Esperar retiros |
| `WithdrawalLimitExceeded()` | Retiro > $1,000 USD | Retirar en múltiples transacciones |
| `StalePrice()` | Precio oracle desactualizado | Esperar actualización de Chainlink |
| `InvalidPrice()` | Precio ≤ 0 | Problema con oracle, contactar admin |
| `AccessControlUnauthorizedAccount` | No tienes el rol requerido | Solo admin/operator |

## 🎯 Casos de Uso

### Caso 1: Usuario Deposita y Retira ETH

```javascript
// 1. Depositar 0.5 ETH
depositNative{value: 0.5 ether}()

// 2. Ver balance
getBalance(myAddress, address(0))
// → 500000000000000000 (0.5 ETH)

// 3. Ver valor en USD
getBalanceInUsd(myAddress, address(0))
// → 1000000000 ($1,000 si ETH = $2,000)

// 4. Retirar 0.2 ETH
withdraw(address(0), 200000000000000000)

// 5. Balance final
getBalance(myAddress, address(0))
// → 300000000000000000 (0.3 ETH)
```

### Caso 2: Admin Agrega Nuevo Token

```javascript
// 1. Verificar rol de admin
hasRole(ADMIN_ROLE, myAddress)
// → true

// 2. Agregar LINK
addToken(
  "0x779877A7B0D9E8603169DdbD7836e478b4624789",
  "0xc59E3633BAAC79493d908e63626716e204A45EdF"
)

// 3. Verificar que se agregó
getSupportedTokens()
// → [address(0), 0x779...]

// 4. Ver info del token
getTokenInfo("0x779877A7B0D9E8603169DdbD7836e478b4624789")
```

### Caso 3: Usuario con Múltiples Tokens

```javascript
// 1. Depositar ETH
depositNative{value: 1 ether}()

// 2. Aprobar y depositar LINK
// En contrato LINK: approve(bankAddress, 100e18)
deposit("0x779...", 100e18)

// 3. Ver todos los balances
getAllBalances(myAddress)
// Retorna:
// tokens: [address(0), 0x779...]
// balances: [1e18, 100e18]
// balancesUsd: [2000000000, 1500000000] // $2k ETH, $1.5k LINK

// 4. Retirar en el token que prefieras
withdrawAll(address(0)) // Retira ETH hasta límite
```

## 📝 Información del Despliegue

- **Red**: Sepolia Testnet
- **Dirección**: `[0xcca76137A214A3A2416d4c45DF87743fB158B52F]`
- **Explorador**: [Ver en Etherscan](https://sepolia.etherscan.io/address/0xcca76137a214a3a2416d4c45df87743fb158b52f)
- **Bank Cap**: $100,000 USD
- **Withdrawal Limit**: $1,000 USD
- **Oracle ETH/USD**: `0x694AA1769357215DE4FAC081bf1f309aDC325306`

## 👤 Autor

**[Imanol Valenzuela]**
- GitHub: [@ImaaValenzuela](https://github.com/ImaaValenzuela)
- LinkedIn: [Imanol Valenzuela](https://www.linkedin.com/in/imanol-valenzuela-eguez/)

## 📄 Licencia

Este proyecto está bajo la Licencia MIT.

## 🙏 Agradecimientos

- **Programa Kipu Web3** - Formación integral en blockchain
- **OpenZeppelin** - Contratos seguros y auditados
- **Chainlink** - Oráculos descentralizados confiables
- **Comunidad Ethereum** - Soporte y recursos

## ⚠️ Disclaimer

Este contrato fue desarrollado con fines educativos. Aunque implementa las mejores prácticas y utiliza librerías auditadas (OpenZeppelin, Chainlink), **NO** ha sido auditado profesionalmente.

**NO** usar en producción con fondos reales sin:
1. Auditoría de seguridad profesional completa
2. Pruebas exhaustivas en testnet
3. Bug bounty program
4. Seguro de protocolo

---

<div align="center">

⭐ **Si este proyecto te fue útil, considera darle una estrella en GitHub** ⭐

🔗 **Contrato en Sepolia**: [Ver en Etherscan](https://sepolia.etherscan.io/address/0x212f9b323de6ddc866106b025c64d916aa7e8e26)

**Made with ❤️ for the Web3 community**

</div>
