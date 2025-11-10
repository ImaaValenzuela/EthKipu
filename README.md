# 🏦 KipuBank V3 - DeFi Banking con Uniswap V2 Integration

![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-5.0-purple)
![Uniswap](https://img.shields.io/badge/Uniswap-V2-pink)
![License](https://img.shields.io/badge/License-MIT-green)
![Coverage](https://img.shields.io/badge/Coverage->50%25-success)

## 🚀 Evolución del Proyecto

KipuBank V3 representa la evolución completa hacia un protocolo DeFi real, integrando Uniswap V2 para aceptar cualquier token y convertirlo automáticamente a USDC.

### 🆚 Comparación de Versiones

| Característica | V2 | V3 |
|---------------|----|----|
| **Tokens aceptados** | Solo whitelisted | Cualquier token en Uniswap V2 |
| **Conversión** | Manual (oráculos) | Automática (swaps) |
| **Contabilidad** | USD normalizado | USDC real |
| **DeFi Integration** | ❌ | ✅ Uniswap V2 |
| **Slippage Protection** | N/A | ✅ Configurable |
| **Path Optimization** | N/A | ✅ Paths customizados |

## 📋 Descripción

KipuBank V3 es un sistema bancario DeFi que:

- ✅ **Acepta cualquier token**: Cualquier token con liquidez en Uniswap V2
- ✅ **Swaps automáticos**: Conversión automática a USDC para contabilidad unificada
- ✅ **Sin dependencia de oráculos**: Usa precios de mercado real de Uniswap
- ✅ **Protección de slippage**: Configurable por admin
- ✅ **Paths optimizados**: Soporte para rutas multi-hop
- ✅ **Control de acceso**: Roles granulares con OpenZeppelin
- ✅ **Límites dinámicos**: Bank cap y límites de retiro en USDC

## 🏗️ Arquitectura

### Flujo de Depósito

```
Usuario deposita Token X
         │
         ▼
    ¿Es USDC?
    /       \
  Sí        No
   │         │
   │         ▼
   │    Swap en Uniswap V2
   │    Token X → USDC
   │         │
   └─────────┘
         │
         ▼
   Validar bankCap
         │
         ▼
   Acreditar USDC
   al balance
```

## 🔑 Características Clave

### 1. Depósitos Generalizados

**Tokens soportados:**
- ✅ ETH nativo (address(0))
- ✅ USDC (directo, sin swap)
- ✅ Cualquier ERC20 con par en Uniswap V2

**Flujo:**
```solidity
// Depositar ETH
kipuBank.depositNative{value: 0.1 ether}()
// ETH → WETH → USDC (automático)

// Depositar USDC
kipuBank.deposit(USDC, 100_000000)
// Acreditado directamente

// Depositar LINK
kipuBank.deposit(LINK, 10 ether)
// LINK → USDC (swap automático)
```

### 2. Integración Uniswap V2

**Swaps automáticos:**
- Usa Uniswap V2 Router para liquidez profunda
- Protección contra slippage configurable
- Paths optimizados (directo o multi-hop)

**Ejemplo de path multi-hop:**
```solidity
// Token raro sin par directo con USDC
// Path: RARE_TOKEN → WETH → USDC
address[] memory path = [RARE_TOKEN, WETH, USDC];
kipuBank.allowToken(RARE_TOKEN, path);
```

### 3. Bank Cap Dinámico

```solidity
// Bank cap: 100,000 USDC
// Depósitos actuales: 95,000 USDC
// Capacidad restante: 5,000 USDC

// Usuario intenta depositar 10 ETH (~$20,000)
// ❌ Revierte: BankCapExceeded

// Usuario deposita 2.5 ETH (~$5,000)
// ✅ Éxito: Alcanza exactamente el cap
```

### 4. Protección de Slippage

```solidity
// Slippage por defecto: 3%
// Usuario deposita cuando:
// - Precio estimado: 1000 USDC
// - Precio mínimo aceptado: 970 USDC (3% menos)

// Si el precio cae a 960 USDC
// ❌ Swap revierte: Slippage excedido

// Si el precio es 980 USDC
// ✅ Swap exitoso: Dentro del tolerance
```

## 📦 Instalación y Setup

### Prerrequisitos

```bash
# Foundry instalado
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Versiones
forge --version  # forge 0.2.0
solc --version   # 0.8.20
```

### Clonar e Instalar

```bash
# Clonar repositorio
git clone https://github.com/ImaaValenzuela/EthKipu
cd kipu-bank-v3

# Instalar dependencias
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# Configurar remappings
echo "@openzeppelin/=lib/openzeppelin-contracts/" > remappings.txt
```

### Compilar

```bash
forge build
```

## 🚀 Despliegue

### Script de Despliegue

Crear `script/DeployKipuBankV3.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KipuBankV3.sol";

contract DeployKipuBankV3 is Script {
    // Sepolia addresses
    address constant UNISWAP_ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    
    uint256 constant BANK_CAP = 100_000_000000; // 100k USDC
    uint256 constant WITHDRAWAL_LIMIT = 10_000_000000; // 10k USDC

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        KipuBankV3 bank = new KipuBankV3(
            UNISWAP_ROUTER,
            USDC,
            BANK_CAP,
            WITHDRAWAL_LIMIT
        );
        
        console.log("KipuBankV3 deployed:", address(bank));
        console.log("Bank Cap:", BANK_CAP / 1e6, "USDC");
        console.log("Withdrawal Limit:", WITHDRAWAL_LIMIT / 1e6, "USDC");
        
        vm.stopBroadcast();
    }
}
```

### Desplegar en Sepolia

```bash
# Configurar .env
echo "SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY" >> .env
echo "PRIVATE_KEY=your_private_key" >> .env
echo "ETHERSCAN_API_KEY=your_etherscan_key" >> .env

# Desplegar y verificar
forge script script/DeployKipuBankV3.s.sol:DeployKipuBankV3 \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  -vvvv
```

## 🔧 Uso del Contrato

### 1. Permitir Nuevos Tokens (Admin)

**Token con path directo:**

```javascript
// LINK tiene par directo con USDC
allowToken(
  "0x779877A7B0D9E8603169DdbD7836e478b4624789", // LINK
  [] // path vacío = usa path directo [LINK, USDC]
)
```

**Token con path multi-hop:**

```javascript
// Token sin par directo, usa WETH como intermediario
allowToken(
  "0xTokenAddress",
  ["0xTokenAddress", "0xWETH", "0xUSDC"] // path custom
)
```

### 2. Depositar ETH

**Método 1: depositNative()**

```javascript
// Via Etherscan Write Contract
depositNative()
// payableAmount: 0.1 (ETH)
```

**Método 2: Transferencia directa**

```javascript
// MetaMask o cualquier wallet
// Enviar ETH directamente a la dirección del contrato
// receive() lo procesa automáticamente
```

### 3. Depositar Tokens ERC20

**Paso 1: Aprobar token**

```javascript
// En el contrato del token
approve(
  KIPUBANK_ADDRESS,
  "10000000000000000000" // 10 tokens (18 decimals)
)
```

**Paso 2: Depositar**

```javascript
// En KipuBankV3
deposit(
  "0x779877A7B0D9E8603169DdbD7836e478b4624789", // LINK
  "10000000000000000000" // 10 LINK
)
// Automáticamente swap LINK → USDC
```

### 4. Estimar Swap

```javascript
// Read Contract
estimateSwap(
  "0x779877A7B0D9E8603169DdbD7836e478b4624789", // LINK
  "10000000000000000000" // 10 LINK
)
// Retorna: cantidad estimada de USDC que recibirás
```

### 5. Consultar Balance

```javascript
getBalance("YOUR_ADDRESS")
// Retorna: balance en USDC (6 decimals)
```

### 6. Retirar USDC

**Retiro específico:**

```javascript
withdraw("1000000000") // 1,000 USDC
```

**Retiro total:**

```javascript
withdrawAll()
// Retira todo (hasta withdrawal limit)
```

### 7. Actualizar Slippage (Admin)

```javascript
updateSlippage(500) // 5% = 500 basis points
// Rango: 0 - 500 (0% - 5%)
```

## 🧪 Testing

### Ejecutar Tests

```bash
# Todos los tests
forge test -vv

# Tests específicos
forge test --match-test testDepositNative -vvvv

# Con cobertura
forge coverage

# Fork test (Sepolia)
forge test --fork-url $SEPOLIA_RPC_URL -vv
```

### Cobertura Mínima

```bash
forge coverage --report summary

# Objetivo: >50%
# File                  % Lines        % Statements   % Branches     % Funcs
# KipuBankV3.sol        85.5%          87.2%          75.0%          90.0%
```

## 📊 Análisis de Amenazas

### Debilidades del Protocolo

1. **Dependencia de Uniswap V2**
   - Riesgo: Si Uniswap tiene problemas, el protocolo se ve afectado
   - Mejora futura: Soporte multi-DEX (Uniswap V3, Sushiswap)

2. **Slippage en mercados volátiles**
   - Riesgo: Swaps pueden fallar en alta volatilidad
   - Mejora futura: Slippage dinámico basado en volatilidad

3. **Sin seguro de fondos**
   - Riesgo: Pérdida total en caso de exploit
   - Mejora futura: Integración con Nexus Mutual

4. **Ausencia de rate limiting**
   - Riesgo: Posible spam de transacciones
   - Mejora futura: Rate limiting por usuario

5. **No hay mecanismo de emergency withdrawal**
   - Riesgo: Fondos bloqueados si hay bug crítico
   - Mejora futura: Emergency mode con retiros directos


## 🎯 Decisiones de Diseño

### 1. ¿Por qué Uniswap V2 y no V3?

**Decisión:** Usar Uniswap V2

**Razones:**
- ✅ Interfaz más simple y predecible
- ✅ Liquidez suficiente para la mayoría de tokens
- ✅ Menor complejidad en paths multi-hop
- ✅ Mejor documentado y probado en batalla

**Trade-off:**
- ❌ Menos eficiente en capital que V3
- ❌ Slippage potencialmente mayor

**Futuro:** Migración a V3 en V4 del protocolo

### 2. ¿Por qué USDC como moneda base?

**Decisión:** Usar USDC para contabilidad

**Razones:**
- ✅ Stablecoin más líquido en DEXs
- ✅ Pares disponibles para casi todos los tokens
- ✅ Estabilidad de precio (menor riesgo)
- ✅ Estándar en DeFi

**Alternativas consideradas:**
- DAI: Menos líquido en algunos pares
- USDT: Problemas de centralización
- Native USD: No existe on-chain

### 3. ¿Por qué Slippage Configurable?

**Decisión:** Slippage ajustable por admin

**Razones:**
- ✅ Flexibilidad en diferentes condiciones de mercado
- ✅ Permite optimizar entre seguridad y UX
- ✅ Admin puede responder a volatilidad

**Protecciones:**
- Máximo 5% (MAX_SLIPPAGE)
- Solo ADMIN_ROLE puede cambiar
- Evento emitido en cada cambio

### 4. ¿Por qué Whitelist de Tokens?

**Decisión:** Admin debe permitir tokens

**Razones:**
- ✅ Previene tokens maliciosos
- ✅ Verifica liquidez antes de permitir
- ✅ Puede configurar paths óptimos
- ✅ Control de calidad

**Trade-off:**
- ❌ Menos permissionless
- ❌ Requiere acción de admin

**Futuro:** Sistema de auto-whitelist basado en liquidez mínima

## 📈 Ejemplos de Uso

### Caso 1: Usuario Casual - Depósito Simple

```javascript
// Alice tiene 0.5 ETH y quiere usar KipuBank

// 1. Alice envía ETH directamente desde MetaMask
// No necesita entender nada técnico
await signer.sendTransaction({
  to: KIPUBANK_ADDRESS,
  value: ethers.parseEther("0.5")
})

// 2. Contrato automáticamente:
//    - Swap 0.5 ETH → USDC
//    - Acredita USDC al balance de Alice
//    - Emite evento Deposit

// 3. Alice verifica su balance
const balance = await kipuBank.getBalance(aliceAddress)
console.log(`Balance: ${ethers.formatUnits(balance, 6)} USDC`)
// "Balance: 1000.00 USDC" (si ETH = $2000)
```

### Caso 2: DeFi Power User - Depósito Optimizado

```javascript
// Bob tiene LINK y quiere mejores retornos

// 1. Estimar cuánto USDC recibirá
const linkAmount = ethers.parseEther("100") // 100 LINK
const estimated = await kipuBank.estimateSwap(LINK, linkAmount)
console.log(`Recibirás: ${ethers.formatUnits(estimated, 6)} USDC`)

// 2. Aprobar y depositar
await linkToken.approve(KIPUBANK_ADDRESS, linkAmount)
await kipuBank.deposit(LINK, linkAmount)

// 3. Verificar transacción
const receipt = await tx.wait()
const depositEvent = receipt.logs.find(log => 
  log.topics[0] === kipuBank.interface.getEventTopic('Deposit')
)
console.log("USDC recibido:", depositEvent.args.amountUsdc)
```

### Caso 3: Admin - Configuración de Token Raro

```javascript
// Token RARE no tiene par directo con USDC
// Admin configura path: RARE → WETH → USDC

// 1. Verificar liquidez en Uniswap
const pair1 = await uniswapFactory.getPair(RARE, WETH)
const pair2 = await uniswapFactory.getPair(WETH, USDC)
// Ambos pares existen ✅

// 2. Configurar path
const path = [RARE, WETH, USDC]
await kipuBank.allowToken(RARE, path)

// 3. Verificar configuración
const configuredPath = await kipuBank.getSwapPath(RARE)
console.log("Path configurado:", configuredPath)
// ["0xRARE", "0xWETH", "0xUSDC"]

// 4. Usuarios ahora pueden depositar RARE
```

## 🔗 Direcciones en Sepolia

### Contratos del Sistema

| Contrato | Dirección | Verificado |
|----------|-----------|------------|
| **KipuBankV3** | `0xd59fd2b8156f8be31d46ae07bff71700e63131e1` | ✅ |
| Uniswap V2 Router | `0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008` | ✅ |
| Uniswap V2 Factory | `0x7E0987E5b3a30e3f2828572Bb659A548460a3003` | ✅ |
| WETH | `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14` | ✅ |

### Tokens de Prueba

| Token | Dirección | Faucet |
|-------|-----------|--------|
| USDC | `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` | [Circle Faucet](https://faucet.circle.com/) |
| LINK | `0x779877A7B0D9E8603169DdbD7836e478b4624789` | [Chainlink Faucet](https://faucets.chain.link/sepolia) |
| DAI | `0x68194a729C2450ad26072b3D33ADaCbcef39D574` | [Aave Faucet](https://staging.aave.com/faucet/) |

## 👤 Autor

**[Imanol Valenzuela]**
- GitHub: [@ImaaValenzuela](https://github.com/ImaaValenzuela)
- LinkedIn: [Imanol Valenzuela](https://www.linkedin.com/in/imanol-valenzuela-eguez/)
  
## 📄 Licencia

MIT License - Ver [LICENSE](LICENSE) para detalles

## 🙏 Agradecimientos

- **Programa Kipu Web3** - Formación integral
- **Uniswap** - Protocolo DEX robusto
- **OpenZeppelin** - Contratos seguros
- **Foundry** - Herramientas de desarrollo

## ⚠️ Disclaimer

Este contrato es un proyecto educativo del programa Kipu Web3. Implementa mejores prácticas y ha sido testeado extensivamente, pero **NO** ha sido auditado profesionalmente.

**NO** usar en producción con fondos reales sin:
1. ✅ Auditoría profesional completa
2. ✅ Bug bounty program activo
3. ✅ Pruebas en testnet por 3+ meses
4. ✅ Seguro de protocolo
5. ✅ Multisig para admin functions

---

<div align="center">

⭐ **Si este proyecto te fue útil, dale una estrella** ⭐

🔗 **Contrato Verificado**: [Ver en Etherscan](https://sepolia.etherscan.io/address/0xd59fd2b8156f8be31d46ae07bff71700e63131e1)

**Made with ❤️ for the Web3 community**

</div>
