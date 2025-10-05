# 🏦 KipuBank - Sistema de Bóveda Bancaria Descentralizada

![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)
![License](https://img.shields.io/badge/License-GNU-000000?logo=gnu&logoColor=white)
![Network](https://img.shields.io/badge/Network-Sepolia-orange)
![Security](https://img.shields.io/badge/Security-Audited-success)

## 📋 Descripción

KipuBank es un contrato inteligente que implementa un sistema de bóveda bancaria descentralizada en Ethereum. Permite a los usuarios depositar y retirar ETH de forma segura, con límites controlados, sistema de pausa de emergencia y siguiendo las mejores prácticas de seguridad auditadas por Etherscan.

### ✨ Características Principales

- ✅ **Depósitos seguros**: Los usuarios pueden depositar ETH con un mínimo de 0.001 ETH
- ✅ **Retiros controlados**: Límite configurable por transacción para mayor seguridad
- ✅ **Retiro total**: Función `withdrawAll()` para retirar todo el balance sin cálculos manuales
- ✅ **Límite global**: Capacidad máxima del banco definida en el despliegue
- ✅ **Circuit Breaker**: Sistema de pausa de emergencia para proteger fondos
- ✅ **Control de acceso**: Solo el owner puede ejecutar funciones administrativas
- ✅ **Eventos transparentes**: Registro completo de todas las operaciones en la blockchain
- ✅ **Errores personalizados**: Mensajes claros y eficientes en gas
- ✅ **Protección contra reentrancy**: Implementa el patrón checks-effects-interactions

## 🔒 Seguridad

Este contrato implementa las mejores prácticas de seguridad recomendadas por Etherscan:

### Patrones Implementados

| Patrón | Descripción |
|--------|-------------|
| **Checks-Effects-Interactions** | Validaciones → Actualización de estado → Interacciones externas |
| **Reentrancy Protection** | Estado se actualiza antes de transferencias |
| **Circuit Breaker** | Sistema de pausa para emergencias |
| **Access Control** | Funciones administrativas restringidas al owner |
| **Custom Errors** | Errores personalizados para ahorrar gas |
| **Safe Transfers** | Uso de `call` en lugar de `transfer` |

## 🏗️ Arquitectura del Contrato

### Variables Inmutables y Constantes

```solidity
uint256 public immutable WITHDRAWAL_LIMIT;  // Límite de retiro por transacción
uint256 public constant MINIMUM_DEPOSIT = 0.001 ether;  // Depósito mínimo
address public immutable owner;  // Propietario del contrato
```

### Variables de Estado

```solidity
uint256 public bankCap;           // Capacidad total del banco
uint256 public totalDeposits;     // Fondos totales depositados
uint256 public depositCount;      // Contador de depósitos
uint256 public withdrawalCount;   // Contador de retiros
bool public paused;               // Estado de pausa del contrato
mapping(address => uint256) public vaults;  // Balances por usuario
```

### Funciones Principales

#### 📥 `deposit()` - External Payable
Deposita ETH en tu bóveda personal.

**Requisitos:**
- Contrato no pausado
- Monto > 0
- Monto ≥ 0.001 ETH
- No exceder el límite del banco

#### 📤 `withdraw(uint256 amount)` - External
Retira una cantidad específica de ETH.

**Requisitos:**
- Contrato no pausado
- Monto > 0
- Balance suficiente
- Monto ≤ WITHDRAWAL_LIMIT

#### 💰 `withdrawAll()` - External
Retira todo tu balance disponible (hasta el límite).

**Ventajas:**
- No necesitas calcular el monto exacto
- Previene errores de cálculo
- Respeta el límite de retiro automáticamente

#### ⏸️ `pause()` - External (Solo Owner)
Pausa el contrato en caso de emergencia.

#### ▶️ `unpause()` - External (Solo Owner)
Reactiva el contrato después de una pausa.

### Funciones de Consulta (View)

| Función | Descripción | Retorno |
|---------|-------------|---------|
| `getBalance(address)` | Balance de cualquier usuario | `uint256` |
| `getMyBalance()` | Tu propio balance | `uint256` |
| `getBankStats()` | Estadísticas del banco | `(uint256, uint256, uint256, uint256)` |
| `isPaused()` | Estado de pausa | `bool` |
| `getMaxWithdrawal(address)` | Máximo retiro disponible | `uint256` |

## 🔧 Cómo Interactuar (Etherscan)

### 1. Ir al Contrato en Etherscan

```
https://sepolia.etherscan.io/address/0x212f9b323de6ddc866106b025c64d916aa7e8e26
```

### 2. Conectar tu Wallet

- Click en "Contract" → "Write Contract"
- Click en "Connect to Web3"
- Conectar MetaMask

### 3. Funciones Disponibles

#### 💵 Depositar ETH

1. Buscar función `deposit`
2. En el campo "deposit (payable)" ingresar el monto en ETH (ej: `0.05`)
3. Click en "Write"
4. Confirmar en MetaMask

#### 💸 Retirar ETH (Monto Específico)

1. Buscar función `withdraw`
2. En el campo `amount (uint256)` ingresar el monto en **wei**
   - Para convertir: `0.05 ETH = 50000000000000000 wei`
   - Usar [ETH Unit Converter](https://eth-converter.com/)
3. Click en "Write"
4. Confirmar en MetaMask

#### 💰 Retirar Todo el Balance

1. Buscar función `withdrawAll`
2. Click en "Write" (no requiere parámetros)
3. Confirmar en MetaMask
4. **Nota**: Si tu balance es mayor al límite (0.1 ETH), solo retirará 0.1 ETH

#### ⏸️ Pausar Contrato (Solo Owner)

1. Buscar función `pause`
2. Click en "Write"
3. Confirmar en MetaMask

#### ▶️ Despausar Contrato (Solo Owner)

1. Buscar función `unpause`
2. Click en "Write"
3. Confirmar en MetaMask

### 4. Consultar Información (Read Contract)

- Click en "Contract" → "Read Contract"
- **No requiere conectar wallet**

#### Ver tu Balance

1. Buscar función `getMyBalance` o `getBalance`
2. Si usas `getBalance`, pegar tu dirección
3. El resultado se muestra en **wei**

#### Ver Estadísticas del Banco

1. Buscar función `getBankStats`
2. Ver los 4 valores retornados:
   - `_totalDeposits`: Total en el banco (wei)
   - `_depositCount`: Número de depósitos
   - `_withdrawalCount`: Número de retiros
   - `_availableCapacity`: Capacidad restante (wei)

#### Verificar Estado de Pausa

1. Buscar función `isPaused`
2. `true` = pausado, `false` = activo

#### Calcular Máximo Retiro

1. Buscar función `getMaxWithdrawal`
2. Ingresar la dirección a consultar
3. Ver el monto máximo que puede retirar en **wei**

## 📊 Conversión de Unidades

| ETH | Wei | Uso |
|-----|-----|-----|
| 0.001 ETH | 1000000000000000 | Depósito mínimo |
| 0.01 ETH | 10000000000000000 | Depósito pequeño |
| 0.1 ETH | 100000000000000000 | Límite de retiro |
| 1 ETH | 1000000000000000000 | Depósito grande |

**Herramienta recomendada**: [ETH Converter](https://eth-converter.com/)

## 🎯 Ejemplos Prácticos

### Escenario 1: Depósito Inicial

```
1. Ir a Write Contract → deposit
2. Ingresar: 0.5 (ETH)
3. Write → Confirmar MetaMask
4. Verificar en Read Contract → getMyBalance
   Resultado: 500000000000000000 (0.5 ETH en wei)
```

### Escenario 2: Retiro Parcial

```
1. Ir a Write Contract → withdraw
2. Ingresar: 50000000000000000 (0.05 ETH en wei)
3. Write → Confirmar MetaMask
4. Verificar nuevo balance: 450000000000000000 (0.45 ETH)
```

### Escenario 3: Retiro Total

```
1. Tener balance: 0.3 ETH
2. Ir a Write Contract → withdrawAll
3. Write → Confirmar MetaMask
4. Resultado: Retira 0.1 ETH (límite)
5. Balance restante: 0.2 ETH
6. Llamar withdrawAll nuevamente para retirar otros 0.1 ETH
```

### Escenario 4: Emergencia (Owner)

```
1. Detectar actividad sospechosa
2. Ir a Write Contract → pause
3. Write → Confirmar MetaMask
4. Verificar: isPaused → true
5. Los usuarios NO pueden depositar ni retirar
6. Investigar el problema
7. Si todo está bien: unpause
```

## 📈 Estadísticas y Monitoreo

### Ver Eventos en Etherscan

1. Ir a "Contract" → "Events"
2. Ver historial de:
   - `Deposit`: Todos los depósitos
   - `Withdrawal`: Todos los retiros
   - `Paused`: Cuándo se pausó
   - `Unpaused`: Cuándo se reactivó

### Filtrar por Dirección

```
1. En "Events" usar el filtro
2. Buscar eventos específicos de tu dirección
3. Ver historial completo de transacciones
```

## 🛡️ Errores Comunes y Soluciones

| Error | Causa | Solución |
|-------|-------|----------|
| `DepositTooSmall()` | Depósito < 0.001 ETH | Depositar mínimo 0.001 ETH |
| `BankCapExceeded()` | Banco lleno | Esperar a que haya retiros |
| `InsufficientBalance()` | No tienes fondos suficientes | Verificar balance con `getMyBalance` |
| `WithdrawalLimitExceeded()` | Intentas retirar > 0.1 ETH | Retirar máximo 0.1 ETH o usar `withdrawAll` |
| `ContractPaused()` | Contrato pausado | Esperar a que el owner lo reactive |
| `OnlyOwner()` | No eres el owner | Solo el owner puede pausar/despausar |
| `TransferFailed()` | Fallo en transferencia | Verificar dirección y gas |

## 📁 Estructura del Repositorio

```
kipu-bank/
├── contracts/
│   └── KipuBank.sol          # Contrato principal
├── .env.example              # Variables de entorno de ejemplo
├── .gitignore               # Archivos a ignorar
├── README.md                # Este archivo
└── LICENSE                  # Licencia MIT
```

## 📝 Información del Contrato Desplegado

- **Red**: Sepolia Testnet
- **Dirección**: `[0x212f9b323de6ddc866106b025c64d916aa7e8e26]`
- **Explorador**: [Ver en Etherscan](https://sepolia.etherscan.io/address/0x212f9b323de6ddc866106b025c64d916aa7e8e26)
- **Owner**: `[0xd7923b9c6484Cf3113570CdC8A8e3f355747B96b]`
- **Bank Cap**: 100 ETH
- **Withdrawal Limit**: 0.1 ETH por transacción
- **Minimum Deposit**: 0.001 ETH

## 🧪 Testing

El contrato ha sido verificado por la IA de Etherscan y cumple con:

- ✅ Uso correcto de SPDX-License-Identifier
- ✅ Variables inmutables y constantes apropiadas
- ✅ Eventos para transparencia
- ✅ Errores personalizados eficientes
- ✅ Modificadores para reducir duplicación
- ✅ Control de acceso implementado
- ✅ Documentación completa con NatSpec
- ✅ Funciones privadas con visibilidad restringida
- ✅ Función withdrawAll para prevenir errores
- ✅ Validación de inputs robusta
- ✅ Circuit breaker para emergencias
- ✅ Protección contra reentrancy

## 👤 Autor

**[Imanol Valenzuela]**
- GitHub: [@ImaaValenzuela](https://github.com/ImaaValenzuela)
- LinkedIn: [Imanol Valenzuela](https://www.linkedin.com/in/imanol-valenzuela-eguez/)

## 🤝 Contribuciones

Este es un proyecto académico del programa Kipu Web3. Las contribuciones son bienvenidas:

1. Fork el proyecto
2. Crea una rama (`git checkout -b feature/mejora`)
3. Commit tus cambios (`git commit -m 'Agrega nueva característica'`)
4. Push a la rama (`git push origin feature/mejora`)
5. Abre un Pull Request

## 📄 Licencia

Este proyecto está bajo la Licencia GPL.

```
GNU License

Copyright (c) 2025 [ImaaValenzuela]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software")...
```

## 🙏 Agradecimientos

- **Programa Kipu Web3** - Por la formación en desarrollo blockchain
- **Comunidad Ethereum** - Por las herramientas y documentación
- **OpenZeppelin** - Por los estándares de seguridad
- **Etherscan** - Por la auditoría y recomendaciones de seguridad

## ⚠️ Disclaimer

Este contrato fue desarrollado con fines educativos como parte del programa Kipu Web3. Aunque implementa las mejores prácticas de seguridad recomendadas por Etherscan, **NO** ha sido auditado profesionalmente. 

**NO** usar en producción con fondos reales sin una auditoría profesional completa.

---

<div align="center">

⭐ **Si este proyecto te fue útil, considera darle una estrella en GitHub** ⭐

🔗 **Contrato en Sepolia**: [Ver en Etherscan](https://sepolia.etherscan.io/address/0x212f9b323de6ddc866106b025c64d916aa7e8e26)

**Made with ❤️ for the Web3 community**

</div>