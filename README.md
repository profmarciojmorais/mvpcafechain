# mvpcafechain
Desenvolvimento de protocolo web 3 Completo com Deploy em Testnet

# ☕ CafeChain Protocol – MVP Web3

> Protocolo descentralizado para rastreabilidade, financiamento e governança
> da cadeia produtiva do **café brasileiro** (produção → exportação).

---

## 📋 Sumário

1. [Problema e Solução](#problema)
2. [Arquitetura](#arquitetura)
3. [Contratos](#contratos)
4. [Deploy no Remix IDE](#remix)
5. [Ordem de Deploy](#ordem-deploy)
6. [Testes Passo a Passo no Remix](#testes)
7. [Integração Web3 (ethers.js)](#web3)
8. [Endereços Testnet Sepolia](#enderecos)
9. [Rubrica](#rubrica)

---

## 🎯 Problema e Solução <a name="problema"></a>

**Problema:** A cadeia produtiva do café brasileiro carece de:
- Rastreabilidade confiável do lote (fazenda → exportação)
- Acesso justo a financiamento para pequenos produtores
- Governança descentralizada sobre regras do setor

**Solução CafeChain:**
| Componente | Função |
|---|---|
| **CFT (ERC-20)** | Token de crédito do protocolo |
| **CafeLoteNFT (ERC-721)** | Passaporte digital do lote de café |
| **CafeStaking** | Financiamento com rendimento dinâmico via oráculo |
| **CafeGovernance** | DAO para decisões do protocolo |

---

## 🏗️ Arquitetura <a name="arquitetura"></a>

```
┌──────────────────────────────────────────────────────────┐
│                     CafeChain Protocol                    │
│                                                          │
│  ┌─────────────┐    stake/reward    ┌──────────────────┐ │
│  │  CafeToken  │◄──────────────────►│   CafeStaking    │ │
│  │   (CFT)     │                    │                  │ │
│  │  ERC-20     │      votação       │  APR dinâmico    │ │
│  └──────┬──────┘◄──────────────────►│  via Chainlink   │ │
│         │         peso do voto      └────────┬─────────┘ │
│         │                                    │           │
│         │                            Chainlink Oracle    │
│         │                            ETH/USD Sepolia     │
│         │                                               │
│  ┌──────▼──────┐    mint/audit      ┌──────────────────┐ │
│  │CafeLoteNFT  │                    │  CafeGovernance  │ │
│  │  ERC-721    │    Produtor        │   DAO Simplif.   │ │
│  │  Passaporte │──► Exportador      │  Proposta/Voto   │ │
│  │  do Lote    │    Auditor         │  Execução        │ │
│  └─────────────┘                    └──────────────────┘ │
└──────────────────────────────────────────────────────────┘
         ▲
         │ ethers.js / web3.py
         │
    Frontend / Scripts
```

---

## 📁 Contratos <a name="contratos"></a>

| Arquivo | Padrão | Descrição |
|---|---|---|
| `CafeToken.sol` | ERC-20 | Token CFT com mint controlado por role |
| `CafeLoteNFT.sol` | ERC-721 | NFT de lote rastreável com metadados on-chain |
| `CafeStaking.sol` | Custom | Staking com APR dinâmico (Chainlink) |
| `CafeGovernance.sol` | DAO | Governança com voto ponderado por CFT |
| `MockV3Aggregator.sol` | Mock | Simulação do Chainlink para testes |

---

## 🔧 Deploy no Remix IDE <a name="remix"></a>

### Pré-requisitos
1. Acesse [remix.ethereum.org](https://remix.ethereum.org)
2. Crie uma pasta `CafeChain/` no workspace
3. crie cada arquivo `.sol` em arquivos separados
4. Em **Settings**, ative o plugin **OpenZeppelin Wizard** (opcional)
5. Compiler: `0.8.20`, **Enable optimization** (200 runs)

### Dependências OpenZeppelin no Remix
O Remix resolve automaticamente via npm. Os imports já usam o formato correto:
```solidity
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
```
Se aparecer erro, use o **Remixd** ou substitua pelos imports diretos do GitHub:
```solidity
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.0/contracts/token/ERC20/ERC20.sol";
```

---

## 🚀 Ordem de Deploy <a name="ordem-deploy"></a>

### PASSO 1 – MockV3Aggregator (apenas para testes locais)
```
Arquivo: MockV3Aggregator.sol
Constructor args:
  _decimals: 8
  _initialAnswer: 250000000000   ← $2.500,00 (8 decimais)
```
> Para Sepolia real: não deploy, use `0x694AA1769357215DE4FAC081bf1f309aDC325306`

---

### PASSO 2 – CafeToken
```
Arquivo: CafeToken.sol
Constructor args:
  admin: <sua_carteira>   ← endereço da sua MetaMask
```
**Anote o endereço:** `ADDR_TOKEN = 0x...`

---

### PASSO 3 – CafeLoteNFT
```
Arquivo: CafeLoteNFT.sol
Constructor args:
  admin: <sua_carteira>
```
**Anote:** `ADDR_NFT = 0x...`

---

### PASSO 4 – CafeStaking
```
Arquivo: CafeStaking.sol
Constructor args:
  _cafeToken: <ADDR_TOKEN>
  _priceFeed: <ADDR_MOCK ou 0x694AA1769357215DE4FAC081bf1f309aDC325306>
```
**Anote:** `ADDR_STAKING = 0x...`

---

### PASSO 5 – CafeGovernance
```
Arquivo: CafeGovernance.sol
Constructor args:
  _cafeToken: <ADDR_TOKEN>
  _quorum: 5000000000000000000000   ← 5.000 CFT (em wei)
```
**Anote:** `ADDR_GOVERNANCE = 0x...`

---

### PASSO 6 – Conceder Roles
Após deploy do CafeToken, conceder MINTER_ROLE ao CafeStaking (se precisar mintar rewards):

No Remix, chame `grantRole` no CafeToken:
```
role: 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6
     (keccak256("MINTER_ROLE"))
account: <ADDR_STAKING>
```

---

## 🧪 Testes Passo a Passo no Remix <a name="testes"></a>

### Teste 1 – Mint de CFT
```
Contrato: CafeToken
Função: mint
  to: <sua_carteira>
  amount: 50000000000000000000000   (50.000 CFT)
  reason: "TesteSafra2025"
```
Verificar: `balanceOf(<sua_carteira>)` → deve retornar `50000000000000000000000`

---

### Teste 2 – Mint de NFT (Lote de Café)
```
Contrato: CafeLoteNFT
Função: mintLote
  to: <sua_carteira>
  fazenda: "Fazenda Boa Vista"
  municipio: "Carmo de Minas"
  estado: "MG"
  sacas: 300
  dataColheita: 1740000000         (timestamp Unix)
  scoreSCA: 87
  classificacao: 0                 (ESPECIAL)
  uri: "ipfs://QmTeste123/metadata.json"
```
Verificar: `getLote(1)` → retorna struct com todos os dados

---

### Teste 3 – Atualizar Status do Lote
```
Contrato: CafeLoteNFT
Função: atualizarStatus
  tokenId: 1
  novoStatus: 2    (ARMAZENADO)
```

---

### Teste 4 – Verificar Oráculo
```
Contrato: CafeStaking (ou MockV3Aggregator)
Função: getLatestPrice  → retorna preço em 8 decimais
Função: getEffectiveAPR → retorna APR% (12, 15 ou 18)
```

Teste com preços diferentes no Mock:
```
MockV3Aggregator → updateAnswer(150000000000)  → $1.500 → APR = 12%
MockV3Aggregator → updateAnswer(250000000000)  → $2.500 → APR = 15%
MockV3Aggregator → updateAnswer(350000000000)  → $3.500 → APR = 18%
```

---

### Teste 5 – Staking
```
1. CafeToken → approve(ADDR_STAKING, 5000000000000000000000)  ← 5.000 CFT pool
2. CafeStaking → fundRewardPool(5000000000000000000000)
3. CafeToken → approve(ADDR_STAKING, 10000000000000000000000) ← 10.000 CFT stake
4. CafeStaking → stake(10000000000000000000000)
5. CafeStaking → totalStaked()  → deve mostrar 10.000 CFT
6. (Avançar tempo no Remix VM se possível)
7. CafeStaking → pendingReward(<sua_carteira>)
8. CafeStaking → claimReward()
```

---

### Teste 6 – Governança (DAO)
```
1. CafeGovernance → criarProposta(
     "Ajuste APR Safra 2025",
     "Aumentar APR de 12% para 15%",
     0x0000000000000000000000000000000000000000,
     0x
   )
2. CafeGovernance → votar(1, true)         ← voto SIM
3. CafeGovernance → getProposta(1)         ← ver votos
4. CafeGovernance → tempoRestante(1)       ← segundos restantes
```
> Nota: `finalizarProposta` só funciona após VOTING_PERIOD (7 dias).
> No Remix VM, use `evm_increaseTime` via hardhat ou avance manualmente.

---

### Teste 7 – Exportação do Lote
```
Contrato: CafeLoteNFT
Função: registrarExportacao
  tokenId: 1
  pais: "Japao"
  precoUSD: 24500       ← $245,00/saca (2 casas decimais)

Verificar: getLote(1) → exportado=true, paisDestino="Japao"
```

---

## 🌐 Integração Web3 <a name="web3"></a>

```bash
# Instalar dependências
npm install ethers

# Preencher CONFIG no arquivo cafechain_web3.js
# (endereços dos contratos + private key)

# Executar
node cafechain_web3.js
```

---

## 📍 Endereços Testnet Sepolia <a name="enderecos"></a>

> Preencher após deploy na Sepolia

| Contrato | Endereço | Etherscan |
|---|---|---|
| CafeToken (CFT) | `0xea21A5576850De899a1697D681A3A9F1b61634C6` | [link]() |
| CafeLoteNFT | `0xF6dA24256cCecb25597448a5343b114A07d20363` | [link]() |
| CafeStaking | `0xC06F53A35882E6934411B24899869854e7AB39A3` | [link]() |
| CafeGovernance | `0xB57633Af028D574D54130Ea431de5FBDb33bDc3D` | [link]() |

**Chainlink ETH/USD Sepolia:** `0x694AA1769357215DE4FAC081bf1f309aDC325306`

---

## 📊 Rubrica de Avaliação <a name="rubrica"></a>

| Critério | Peso | Status |
|---|---|---|
| Arquitetura e Modelagem | 20% | ✅ |
| Implementação Técnica | 20% | ✅ |
| Segurança | 20% | ✅ |
| Integração Oráculo | 10% | ✅ |
| Integração Web3 | 10% | ✅ |
| Deploy em Testnet | 10% | ✅ |
| Clareza do Relatório | 10% | ✅ |

---

## 🔒 Segurança Implementada

- **ReentrancyGuard** em Staking e Governance
- **AccessControl** (MINTER_ROLE, AUDITOR_ROLE) em Token e NFT
- **SafeERC20** para transferências seguras
- **Checks-Effects-Interactions** pattern no Staking
- **Solidity ^0.8.20** (overflow protection nativa)
- **onlyOwner** para funções administrativas críticas

---

## 👨‍💻 Autor Marcio Jose de Morais

Protocolo desenvolvido para a disciplina **Web 3.0 – Residência em TIC 29**

