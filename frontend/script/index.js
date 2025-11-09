        // Configuración
        const CONTRACT_ADDRESS = '0xd59fd2b8156f8be31d46ae07bff71700e63131e1';
        const SEPOLIA_CHAIN_ID = '0xaa36a7'; // 11155111 in hex
        
        const CONTRACT_ABI = [
            "function depositNative() external payable",
            "function deposit(address token, uint256 amount) external",
            "function withdraw(uint256 amount) external",
            "function withdrawAll() external",
            "function getBalance(address user) external view returns (uint256)",
            "function getBankStats() external view returns (uint256, uint256, uint256, uint256)",
            "function estimateSwap(address tokenIn, uint256 amountIn) external view returns (uint256)",
            "function isTokenAllowed(address token) external view returns (bool)",
            "function bankCap() external view returns (uint256)",
            "function withdrawalLimit() external view returns (uint256)",
            "event Deposit(address indexed user, address indexed tokenIn, uint256 amountIn, uint256 amountUsdc)",
            "event Withdrawal(address indexed user, uint256 amount)"
        ];

        const ERC20_ABI = [
            "function approve(address spender, uint256 amount) external returns (bool)",
            "function allowance(address owner, address spender) external view returns (uint256)",
            "function balanceOf(address account) external view returns (uint256)"
        ];

        let provider, signer, contract, userAddress;

        // Connect Wallet
        document.getElementById('connectBtn').addEventListener('click', async () => {
            try {
                if (typeof window.ethereum === 'undefined') {
                    alert('Please install MetaMask!');
                    return;
                }

                await window.ethereum.request({ method: 'eth_requestAccounts' });
                provider = new ethers.providers.Web3Provider(window.ethereum);
                signer = provider.getSigner();
                userAddress = await signer.getAddress();
                contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

                // Check network
                const network = await provider.getNetwork();
                if (network.chainId !== 11155111) {
                    try {
                        await window.ethereum.request({
                            method: 'wallet_switchEthereumChain',
                            params: [{ chainId: SEPOLIA_CHAIN_ID }],
                        });
                    } catch (error) {
                        alert('Please switch to Sepolia Testnet');
                        return;
                    }
                }

                document.getElementById('connectBtn').textContent = `${userAddress.slice(0, 6)}...${userAddress.slice(-4)}`;
                document.getElementById('userAddress').textContent = `${userAddress.slice(0, 10)}...${userAddress.slice(-8)}`;
                document.getElementById('networkBadge').textContent = 'Sepolia';
                document.getElementById('networkBadge').style.background = '#4caf50';
                document.getElementById('networkBadge').style.color = 'white';

                await updateBalances();
                setupEventListeners();

            } catch (error) {
                console.error('Connection error:', error);
                alert('Failed to connect wallet');
            }
        });

        // Update Balances
        async function updateBalances() {
            try {
                const balance = await contract.getBalance(userAddress);
                const formattedBalance = ethers.utils.formatUnits(balance, 6);
                document.getElementById('userBalance').textContent = `${parseFloat(formattedBalance).toFixed(2)} USDC`;

                const stats = await contract.getBankStats();
                document.getElementById('totalDeposits').textContent = `${ethers.utils.formatUnits(stats[0], 6)} USDC`;
                
                const bankCap = await contract.bankCap();
                document.getElementById('bankCapacity').textContent = `${ethers.utils.formatUnits(bankCap, 6)} USDC`;
                
                document.getElementById('depositCount').textContent = stats[1].toString();
                document.getElementById('withdrawalCount').textContent = stats[2].toString();

                // Max withdrawal
                const withdrawalLimit = await contract.withdrawalLimit();
                const maxWithdraw = balance.gt(withdrawalLimit) ? withdrawalLimit : balance;
                document.getElementById('maxWithdrawal').textContent = `${ethers.utils.formatUnits(maxWithdraw, 6)} USDC`;

            } catch (error) {
                console.error('Error updating balances:', error);
            }
        }

        // Setup Event Listeners
        function setupEventListeners() {
            // Estimate Deposit
            document.getElementById('estimateDepositBtn').addEventListener('click', async () => {
                try {
                    const token = document.getElementById('depositToken').value;
                    const amount = document.getElementById('depositAmount').value;
                    
                    if (!amount || amount <= 0) {
                        alert('Please enter a valid amount');
                        return;
                    }

                    let estimate;
                    if (token === 'native') {
                        const amountWei = ethers.utils.parseEther(amount);
                        estimate = await contract.estimateSwap(ethers.constants.AddressZero, amountWei);
                    } else {
                        const tokenContract = new ethers.Contract(token, ERC20_ABI, signer);
                        const decimals = token === '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238' ? 6 : 18;
                        const amountWei = ethers.utils.parseUnits(amount, decimals);
                        estimate = await contract.estimateSwap(token, amountWei);
                    }

                    const estimateFormatted = ethers.utils.formatUnits(estimate, 6);
                    document.getElementById('depositEstimateValue').textContent = `${parseFloat(estimateFormatted).toFixed(2)} USDC`;
                    document.getElementById('depositEstimate').classList.add('active');

                } catch (error) {
                    console.error('Estimate error:', error);
                    alert('Failed to estimate. Token might not be allowed or amount too low.');
                }
            });

            // Deposit
            document.getElementById('depositBtn').addEventListener('click', async () => {
                try {
                    const token = document.getElementById('depositToken').value;
                    const amount = document.getElementById('depositAmount').value;
                    
                    if (!amount || amount <= 0) {
                        alert('Please enter a valid amount');
                        return;
                    }

                    document.getElementById('depositLoading').classList.add('active');
                    document.getElementById('depositSuccess').classList.remove('active');
                    document.getElementById('depositError').classList.remove('active');

                    let tx;
                    if (token === 'native') {
                        const amountWei = ethers.utils.parseEther(amount);
                        tx = await contract.depositNative({ value: amountWei });
                    } else {
                        const tokenContract = new ethers.Contract(token, ERC20_ABI, signer);
                        const decimals = token === '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238' ? 6 : 18;
                        const amountWei = ethers.utils.parseUnits(amount, decimals);

                        // Check allowance
                        const allowance = await tokenContract.allowance(userAddress, CONTRACT_ADDRESS);
                        if (allowance.lt(amountWei)) {
                            const approveTx = await tokenContract.approve(CONTRACT_ADDRESS, ethers.constants.MaxUint256);
                            await approveTx.wait();
                        }

                        tx = await contract.deposit(token, amountWei);
                    }

                    const receipt = await tx.wait();
                    
                    document.getElementById('depositLoading').classList.remove('active');
                    document.getElementById('depositSuccess').innerHTML = `
                        ✅ Deposit successful! 
                        <a href="https://sepolia.etherscan.io/tx/${receipt.transactionHash}" target="_blank" class="tx-link">View on Etherscan</a>
                    `;
                    document.getElementById('depositSuccess').classList.add('active');

                    document.getElementById('depositAmount').value = '';
                    document.getElementById('depositEstimate').classList.remove('active');
                    await updateBalances();

                } catch (error) {
                    console.error('Deposit error:', error);
                    document.getElementById('depositLoading').classList.remove('active');
                    document.getElementById('depositError').textContent = `❌ Error: ${error.message || 'Transaction failed'}`;
                    document.getElementById('depositError').classList.add('active');
                }
            });

            // Withdraw
            document.getElementById('withdrawBtn').addEventListener('click', async () => {
                try {
                    const amount = document.getElementById('withdrawAmount').value;
                    
                    if (!amount || amount <= 0) {
                        alert('Please enter a valid amount');
                        return;
                    }

                    document.getElementById('withdrawLoading').classList.add('active');
                    document.getElementById('withdrawSuccess').classList.remove('active');
                    document.getElementById('withdrawError').classList.remove('active');

                    const amountWei = ethers.utils.parseUnits(amount, 6);
                    const tx = await contract.withdraw(amountWei);
                    const receipt = await tx.wait();
                    
                    document.getElementById('withdrawLoading').classList.remove('active');
                    document.getElementById('withdrawSuccess').innerHTML = `
                        ✅ Withdrawal successful! 
                        <a href="https://sepolia.etherscan.io/tx/${receipt.transactionHash}" target="_blank" class="tx-link">View on Etherscan</a>
                    `;
                    document.getElementById('withdrawSuccess').classList.add('active');

                    document.getElementById('withdrawAmount').value = '';
                    await updateBalances();

                } catch (error) {
                    console.error('Withdraw error:', error);
                    document.getElementById('withdrawLoading').classList.remove('active');
                    document.getElementById('withdrawError').textContent = `❌ Error: ${error.message || 'Transaction failed'}`;
                    document.getElementById('withdrawError').classList.add('active');
                }
            });

            // Withdraw All
            document.getElementById('withdrawAllBtn').addEventListener('click', async () => {
                try {
                    document.getElementById('withdrawLoading').classList.add('active');
                    document.getElementById('withdrawSuccess').classList.remove('active');
                    document.getElementById('withdrawError').classList.remove('active');

                    const tx = await contract.withdrawAll();
                    const receipt = await tx.wait();
                    
                    document.getElementById('withdrawLoading').classList.remove('active');
                    document.getElementById('withdrawSuccess').innerHTML = `
                        ✅ Withdrawal successful! 
                        <a href="https://sepolia.etherscan.io/tx/${receipt.transactionHash}" target="_blank" class="tx-link">View on Etherscan</a>
                    `;
                    document.getElementById('withdrawSuccess').classList.add('active');

                    await updateBalances();

                } catch (error) {
                    console.error('Withdraw all error:', error);
                    document.getElementById('withdrawLoading').classList.remove('active');
                    document.getElementById('withdrawError').textContent = `❌ Error: ${error.message || 'Transaction failed'}`;
                    document.getElementById('withdrawError').classList.add('active');
                }
            });
        }

        // Listen to account changes
        if (window.ethereum) {
            window.ethereum.on('accountsChanged', (accounts) => {
                if (accounts.length === 0) {
                    location.reload();
                } else {
                    location.reload();
                }
            });

            window.ethereum.on('chainChanged', () => {
                location.reload();
            });
        }