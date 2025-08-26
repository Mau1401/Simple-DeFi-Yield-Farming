// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./DAppToken.sol";
import "./LPToken.sol";

/**
 * @title Proportional Token Farm
 * @notice Una granja de staking donde las recompensas se distribuyen proporcionalmente al total stakeado.
 */
contract TokenFarm {
    //
    // Variables de estado
    //
    string public name = "Proportional Token Farm";
    address public owner;
    DAppToken public dappToken;
    LPToken public lpToken;

    uint256 public constant REWARD_PER_BLOCK = 1e18; // Recompensa por bloque (total para todos los usuarios)
    uint256 public totalStakingBalance; // Total de tokens en staking

    address[] public stakers;
    
    // Bonus 2: Struct
    struct structUser {
        uint256 stakingBalance;
        uint256 checkpoints;
        uint256 pendingRewards;
        bool hasStaked;
        bool isStaking;
    }
    mapping(address => structUser) public usersInfo;
    // mapping(address => uint256) public stakingBalance;
    // mapping(address => uint256) public checkpoints;
    // mapping(address => uint256) public pendingRewards;
    // mapping(address => bool) public hasStaked;
    // mapping(address => bool) public isStaking;

   
    // Eventos
    // Agregar eventos para Deposit, Withdraw, RewardsClaimed y RewardsDistributed.
    event  SuccessDeposit(address indexed user, uint256 amount);
    event  SuccessWithdraw(address indexed user, uint256 amount);
    event  SuccessClaimRewards(address indexed user,uint256 pendingAmount);
    event  RewardsDistributed(address indexed beneficiary, uint256 reward);

    // Bonus 1: Modifier
    modifier OnlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
        
    }

    modifier OnlyStaker() {
        require(usersInfo[msg.sender].isStaking && usersInfo[msg.sender].stakingBalance != 0, "You are not staking");
        _;
    }

    // Constructor
    constructor(DAppToken _dappToken, LPToken _lpToken) {
        // Configurar las instancias de los contratos de DappToken y LPToken.
        dappToken = _dappToken;
        lpToken = _lpToken;
        // Configurar al owner del contrato como el creador de este contrato.
        owner = msg.sender;
    }

    /**
     * @notice Deposita tokens LP para staking.
     * @param _amount Cantidad de tokens LP a depositar.
     */
    function deposit(uint256 _amount) external {
        // Verificar que _amount sea mayor a 0.
        require(_amount > 0, "Amount must be greater than 0");
        // Transferir tokens LP del usuario a este contrato.
        lpToken.transferFrom(msg.sender, address(this), _amount);
        // Actualizar el balance de staking del usuario en stakingBalance.
        structUser storage user = usersInfo[msg.sender]; // variable de storage
        user.stakingBalance += _amount;
        // Incrementar totalStakingBalance con _amount.
        totalStakingBalance += _amount;
        // Si el usuario nunca ha hecho staking antes, agregarlo al array stakers y marcar hasStaked como true.
        if (!user.hasStaked) {
            stakers.push(msg.sender);
            user.hasStaked = true;
        }
        // Actualizar isStaking del usuario a true.
        user.isStaking = true;
        // Si checkpoints del usuario está vacío, inicializarlo con el número de bloque actual.
        if (user.checkpoints == 0) {
            user.checkpoints = block.number;
        } else {
            // Llamar a distributeRewards para calcular y actualizar las recompensas pendientes.
            distributeRewards(msg.sender);
            // Emitir un evento de depósito.
        }
        emit SuccessDeposit(msg.sender, _amount);
    }

    /**
     * @notice Retira todos los tokens LP en staking.
     */
    function withdraw() external OnlyStaker {
        // Verificar que el usuario está haciendo staking (isStaking == true).
        // require(isStaking[msg.sender], "You are not staking");
        // Obtener el balance de staking del usuario.
        structUser storage user = usersInfo[msg.sender]; // variable de storage

        uint256 balance = user.stakingBalance;
        // Verificar que el balance de staking sea mayor a 0.
        require(balance > 0, "No staking balance to withdraw");
        // Llamar a distributeRewards para calcular y actualizar las recompensas pendientes antes de restablecer el balance.
        distributeRewards(msg.sender);
        // Restablecer stakingBalance del usuario a 0.
        user.stakingBalance = 0;
        // Reducir totalStakingBalance en el balance que se está retirando.
        totalStakingBalance -= balance;
        // Actualizar isStaking del usuario a false.
        user.isStaking = false;
        // Transferir los tokens LP de vuelta al usuario.
        lpToken.transfer(msg.sender, balance);
        // Emitir un evento de retiro.
        emit SuccessWithdraw(msg.sender, balance);
    }

    /**
     * @notice Reclama recompensas pendientes.
     */
    function claimRewards() external {
        structUser storage user = usersInfo[msg.sender]; // variable de storage
        // Obtener el monto de recompensas pendientes del usuario desde pendingRewards.
        uint256 pendingAmount = user.pendingRewards;
        // Verificar que el monto de recompensas pendientes sea mayor a 0.
        require(pendingAmount > 0, "No rewards to claim");
        // Restablecer las recompensas pendientes del usuario a 0.
        user.pendingRewards = 0;
        // Llamar a la función de acuñación (mint) en el contrato DappToken para transferir las recompensas al usuario.
        dappToken.mint(msg.sender, pendingAmount);
        // Emitir un evento de reclamo de recompensas.
        emit SuccessClaimRewards(msg.sender, pendingAmount);
    }

    /**
     * @notice Distribuye recompensas a todos los usuarios en staking.
     */
    function distributeRewardsAll() external OnlyOwner {
        // Verificar que la llamada sea realizada por el owner.
        // require(msg.sender == owner, "Only owner can distribute rewards");

        // Iterar sobre todos los usuarios en staking almacenados en el array stakers.
        for(uint256 i = 0; i < stakers.length; i++) {
            address beneficiary = stakers[i];
            structUser storage user = usersInfo[beneficiary]; // variable de storage
            // Para cada usuario, si están haciendo staking (isStaking == true), llamar a distributeRewards.
            if(user.isStaking) {
                distributeRewards(beneficiary);
            }

            // Emitir un evento indicando que las recompensas han sido distribuidas.
            emit RewardsDistributed(beneficiary, user.pendingRewards);
        }
        
    }

    /**
     * @notice Calcula y distribuye las recompensas proporcionalmente al staking total.
     * @dev La función toma en cuenta el porcentaje de tokens que cada usuario tiene en staking con respecto
     *      al total de tokens en staking (`totalStakingBalance`).
     *
     * Funcionamiento:
     * 1. Se calcula la cantidad de bloques transcurridos desde el último checkpoint del usuario.
     * 2. Se calcula la participación proporcional del usuario:
     *    share = stakingBalance[beneficiary] / totalStakingBalance
     * 3. Las recompensas para el usuario se determinan multiplicando su participación proporcional
     *    por las recompensas por bloque (`REWARD_PER_BLOCK`) y los bloques transcurridos:
     *    reward = REWARD_PER_BLOCK * blocksPassed * share
     * 4. Se acumulan las recompensas calculadas en `pendingRewards[beneficiary]`.
     * 5. Se actualiza el checkpoint del usuario al bloque actual.
     *
     * Ejemplo Práctico:
     * - Supongamos que:
     *    Usuario A ha stakeado 100 tokens.
     *    Usuario B ha stakeado 300 tokens.
     *    Total de staking (`totalStakingBalance`) = 400 tokens.
     *    `REWARD_PER_BLOCK` = 1e18 (1 token total por bloque).
     *    Han transcurrido 10 bloques desde el último checkpoint.
     *
     * Cálculo:
     * - Participación de Usuario A:
     *   shareA = 100 / 400 = 0.25 (25%)
     *   rewardA = 1e18 * 10 * 0.25 = 2.5e18 (2.5 tokens).
     *
     * - Participación de Usuario B:
     *   shareB = 300 / 400 = 0.75 (75%)
     *   rewardB = 1e18 * 10 * 0.75 = 7.5e18 (7.5 tokens).
     *
     * Resultado:
     * - Usuario A acumula 2.5e18 en `pendingRewards`.
     * - Usuario B acumula 7.5e18 en `pendingRewards`.
     *
     * Nota:
     * Este sistema asegura que las recompensas se distribuyan proporcionalmente y de manera justa
     * entre todos los usuarios en función de su contribución al staking total.
     */
    function distributeRewards(address beneficiary) private {
        // Obtener el último checkpoint del usuario desde checkpoints.
        structUser storage user = usersInfo[beneficiary]; // variable de storage
        uint256 checkpoint = user.checkpoints;

        // Verificar que el número de bloque actual sea mayor al checkpoint y que totalStakingBalance sea mayor a 0.
        require(block.number > checkpoint, "No blocks passed since last checkpoint");
        require(totalStakingBalance > 0, "No staking balance available");
        
        if (user.isStaking && user.stakingBalance > 0) {
            // Calcular la cantidad de bloques transcurridos desde el último checkpoint.
            uint256 blocksPassed = block.number - checkpoint;

            if (blocksPassed > 0){
                // Calcular la proporción del staking del usuario en relación al total staking (stakingBalance[beneficiary] / totalStakingBalance).
                uint256 share = user.stakingBalance/ totalStakingBalance;
                
                // Calcular las recompensas del usuario multiplicando la proporción por REWARD_PER_BLOCK y los bloques transcurridos.
                uint256 reward = REWARD_PER_BLOCK * blocksPassed * share;
                
                // Actualizar las recompensas pendientes del usuario en pendingRewards.
                user.pendingRewards += reward;

                // Actualizar el checkpoint del usuario al bloque actual.
                user.checkpoints = block.number;

                emit RewardsDistributed(beneficiary, reward);
            }
            
        }
    }

}