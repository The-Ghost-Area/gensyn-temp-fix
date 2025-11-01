#!/bin/bash
# =========================================================
# 🐝 Temporary Fix Script for [Errno 111] Connection Refused
# Author: The Ghost Area / Gensyn Temp Fix
# =========================================================

echo ""
echo "🔧 Starting temporary fix for rl-swarm connection issue..."
echo "---------------------------------------------------------"

# Step 1: Go to rl-swarm directory
if [ ! -d "rl-swarm" ]; then
  echo "❌ rl-swarm directory not found!"
  echo "➡️  Please run this script from the parent directory where 'rl-swarm' folder exists."
  exit 1
fi

cd rl-swarm || exit
echo "📂 Changed directory to $(pwd)"

# Step 2: Update node
echo ""
echo "🪄 Updating your rl-swarm node..."
git stash >/dev/null 2>&1
git pull || { echo "❌ Git pull failed! Check your network or branch."; exit 1; }

# Step 3: Remove old manager.py
TARGET_FILE="rgym_exp/src/manager.py"
if [ -f "$TARGET_FILE" ]; then
  echo ""
  echo "🗑️  Removing old manager.py..."
  sudo rm "$TARGET_FILE"
else
  echo ""
  echo "⚠️  manager.py not found, skipping removal."
fi

# Step 4: Recreate manager.py with fixed version
echo ""
echo "🧩 Recreating manager.py with new fixed code..."
sudo mkdir -p rgym_exp/src
sudo tee "$TARGET_FILE" > /dev/null <<'EOF'
import os
os.environ["TOKENIZERS_PARALLELISM"] = "false"
import time
from collections import defaultdict
import subprocess
import re
import logging
logging.getLogger("hivemind").setLevel(logging.CRITICAL)

from genrl.blockchain import SwarmCoordinator
from genrl.communication import Communication
from genrl.communication.hivemind.hivemind_backend import HivemindBackend
from genrl.data import DataManager
from genrl.game import BaseGameManager
from genrl.game.game_manager import DefaultGameManagerMixin
from genrl.logging_utils.global_defs import get_logger
from genrl.logging_utils.system_utils import get_system_info
from genrl.rewards import RewardManager
from genrl.roles import RoleManager
from genrl.state import GameState
from genrl.trainer import TrainerModule
from huggingface_hub import login, whoami
from hivemind import DHT

from rgym_exp.src.utils.name_utils import get_name_from_peer_id
from rgym_exp.src.prg_module import PRGModule


class SwarmGameManager(BaseGameManager, DefaultGameManagerMixin):
    """GameManager that orchestrates a game using a SwarmCoordinator."""

    def __init__(
        self,
        coordinator: SwarmCoordinator,
        max_stage: int,
        max_round: int,
        game_state: GameState,
        reward_manager: RewardManager,
        trainer: TrainerModule,
        data_manager: DataManager,
        communication: Communication,
        role_manager: RoleManager | None = None,
        run_mode: str = "train",
        log_dir: str = "logs",
        hf_token: str | None = None,
        hf_push_frequency: int = 20,
        **kwargs,
    ):
        super().__init__(
            max_stage=max_stage,
            max_round=max_round,
            game_state=game_state,
            reward_manager=reward_manager,
            trainer=trainer,
            data_manager=data_manager,
            communication=communication,
            role_manager=role_manager,
            run_mode=run_mode,
        )

        assert isinstance(self.communication, HivemindBackend)
        self.train_timeout = 60 * 60 * 24 * 31  # 1 month

        self.peer_id = self.communication.get_id()
        self.state.peer_id = self.peer_id
        self.animal_name = get_name_from_peer_id(self.peer_id, True)

        self.coordinator = coordinator
        self.coordinator.register_peer(self.peer_id)
        round, _ = self.coordinator.get_round_and_stage()
        self.state.round = round

        self.communication.step_ = self.state.round

        self.hf_token = hf_token
        if self.hf_token not in [None, "None"]:
            self._configure_hf_hub(hf_push_frequency)

        get_logger().info(f"🐱 Hello 🐈 [{get_name_from_peer_id(self.peer_id)}] 🦮 [{self.peer_id}]!")
        get_logger().info(f"bootnodes: {kwargs.get('bootnodes', [])}")
        get_logger().info(f"Using Model: {self.trainer.model.config.name_or_path}")

        with open(os.path.join(log_dir, f"system_info.txt"), "w") as f:
            f.write(get_system_info())

        self.batched_signals = 0.0
        self.time_since_submit = time.time()
        self.submit_period = 3.0
        self.submitted_this_round = False

        self.prg_module = PRGModule(log_dir, **kwargs)
        self.prg_game = self.prg_module.prg_game
        self.bootnodes = kwargs.get('bootnodes', [])

    def find_existing_p2pd(self):
        try:
            result = subprocess.run(['ss', '-tlpn'], capture_output=True, text=True)
            output = result.stdout
            if 'p2pd' in output:
                tcp_match = re.search(r'.*:(\d+).*p2pd.*tcp', output)
                udp_match = re.search(r'.*:(\d+).*p2pd.*udp', output)
                if tcp_match and udp_match:
                    return [
                        f"/ip4/0.0.0.0/tcp/{tcp_match.group(1)}",
                        f"/ip4/0.0.0.0/udp/{udp_match.group(1)}/quic"
                    ]
            return None
        except:
            return None
EOF

echo ""
echo "✅ manager.py replaced successfully!"
echo "🧹 Cleanup complete."

echo ""
echo "🚀 All done!"
echo "Now you can rerun your node as usual:"
echo ""
echo "  cd ~/rl-swarm"
echo "  python run.py"
echo ""
echo "🐝 Happy Swarming!"
echo "---------------------------------------------------------"
