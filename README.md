# Decentralized Stablecoin System (DSC)
*A fully over‑collateralized, algorithmic stablecoin protocol built with Solidity & Foundry.*

---

## 📌 Overview

This project implements a minimal yet robust decentralized stablecoin system inspired by MakerDAO’s DAI architecture. It demonstrates real‑world DeFi engineering skills, including:

- Over‑collateralized debt positions  
- Health‑factor–based risk management  
- Liquidation mechanics  
- Oracle‑secured pricing  
- ERC‑20 minting/burning with strict access control  
- Stateful fuzzing and invariant testing  

The system consists of two core contracts:

### **1. `DecentralizedStableCoin` (DSC)**
A mintable/burnable ERC‑20 token governed exclusively by the DSCEngine.

### **2. `DSCEngine`**
The protocol’s core logic:
- Deposit collateral  
- Mint DSC  
- Burn DSC  
- Redeem collateral  
- Liquidate unhealthy positions  
- Enforce health factor invariants  
- Integrate Chainlink‑style price feeds  

This project is **not intended for mainnet**, but it *is* engineered to production standards for portfolio demonstration.

---

## 🧱 Architecture

src/  
│  
├── DecentralizedStableCoin.sol   # ERC20 stablecoin  
├── DSCEngine.sol                 # Core protocol logic  
└── libraries/  
  └── OracleLib.sol             # Price feed safety checks  

script/  
│  
├── DeployDSC.s.sol               # Deployment script  
└── HelperConfig.s.sol            # Network config + mocks  

test/  
│  
├── unit/  
│  ├── DecentralizedStableCoinTest.t.sol  
│  └── DSCEngineTest.t.sol  
│  
├── fuzz/  
│  ├── Handler.t.sol             # Stateful fuzz handler  
│  └── Invariants.t.sol          # Invariant tests  
│  
└── mocks/  
   ├── ERC20Mock.sol  
   └── MockV3Aggregator.sol  

---

## ⚙️ Features

### ✔ Over‑Collateralization
Users must maintain a health factor ≥ 1.0 to avoid liquidation.

### ✔ Liquidation Mechanism
If a user’s health factor falls below the threshold:
- Liquidators burn DSC  
- Receive collateral + liquidation bonus  

### ✔ Oracle Safety
`OracleLib` enforces:
- Non‑zero prices  
- Non‑stale data  
- Correct decimals  

### ✔ SafeERC20 Everywhere
No unchecked ERC‑20 transfers.  
No silent failures.

### ✔ Full Invariant Testing
The system is fuzz‑tested with:
- Random deposits  
- Random minting  
- Random redemptions  
- Random burns  
- Random liquidations  
- Random price movements  

**Invariant pass rate: 100% across ~25,600 calls.**

---

## 🚀 Getting Started

### Prerequisites
- Foundry  
- Git  
- A terminal  

### Install dependencies
forge install

### Build
forge build

### Run tests
forge test

### Run with verbose logs
forge test -vvv

### Run invariant tests
forge test --match-test invariant -vvv

---

## 🧪 Testing Philosophy

This project uses **three layers of testing**:

### **1. Unit Tests**
Validate individual functions:
- deposit  
- mint  
- burn  
- redeem  
- liquidation  
- oracle behavior  

### **2. Stateful Fuzzing (`Handler`)**
Simulates chaotic user behavior:
- Random deposits  
- Random minting  
- Random redemptions  
- Random burns  
- Random liquidations  
- Random price drops  

The handler respects protocol rules (e.g., health factor), making the fuzzing realistic.

### **3. Invariant Tests**
Key invariants include:

#### **Invariant 1: Protocol must always be over‑collateralized**
totalCollateralValue >= totalDSCMinted

#### **Invariant 2: No user can have HF < 1 unless liquidatable**
Health factor is always enforced.

#### **Invariant 3: DSC supply must never exceed collateral value**
Minting is always bounded by collateral.

#### **Invariant 4: Oracle data must always be valid**
Stale or zero prices revert.

**All invariants pass under 25k+ random operations.**

---

## 📊 Health Factor Formula

HF = (CollateralValue * LiquidationThreshold) / Debt

If HF < 1 → liquidation allowed.

---

## 🛡 Security Considerations

Even though this is a portfolio project, it includes real‑world protections:

- ReentrancyGuard  
- SafeERC20  
- Oracle validation  
- Overflow/underflow safety  
- Strict access control  
- Health factor enforcement  

---

## 🧩 What This Project Demonstrates

This codebase highlights practical, production‑aligned skills that matter in real DeFi engineering roles:

### **✔ Mastery of Core Solidity Concepts**
- Safe external calls  
- Access control  
- Immutable variables  
- Custom errors  
- Reentrancy protection  
- ERC‑20 mechanics  

### **✔ Ability to Design Real Protocol Logic**
- Collateralized debt positions  
- Liquidation incentives  
- Health factor enforcement  
- Oracle‑driven pricing  
- System‑wide safety constraints  

### **✔ Strong Testing Culture**
- Comprehensive unit tests  
- Stateful fuzzing with realistic constraints  
- Invariant testing across thousands of random operations  
- Mocking oracles and ERC‑20s  
- Event validation  

### **✔ Production‑minded Engineering**
- Separation of concerns  
- Clear architecture  
- Defensive programming  
- Gas‑aware patterns  
- Readable, maintainable code  

### **✔ Understanding of DeFi Risk & Failure Modes**
- Oracle manipulation  
- Under‑collateralization  
- Liquidation edge cases  
- ERC‑20 non‑standard behavior  
- Price feed staleness  

This project shows that you can build something **complex, safe, and correct**—the exact combination recruiters look for in Solidity engineers.

---

## 📄 License

MIT
