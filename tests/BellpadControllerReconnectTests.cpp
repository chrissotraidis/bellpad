#include "controller_reconcile.hpp"

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <vector>

using aurora::input::detail::ControllerReconcilePlan;
using aurora::input::detail::ControllerSnapshot;
using aurora::input::detail::plan_controller_reconciliation;

namespace {

struct PadState {
  uint16_t buttons = 0;
  int16_t stickX = 0;
  int16_t stickY = 0;
  int16_t cStickX = 0;
  int16_t cStickY = 0;
  uint8_t leftTrigger = 0;
  uint8_t rightTrigger = 0;
};

struct FakeController {
  uint32_t instance = 0;
  int32_t player = -1;
  PadState state;
};

void applyPlan(std::vector<FakeController>& controllers, const ControllerReconcilePlan& plan) {
  for (uint32_t instance : plan.close) {
    std::erase_if(controllers, [instance](const FakeController& controller) {
      return controller.instance == instance;
    });
  }
  for (const auto& assignment : plan.assign) {
    controllers.push_back({assignment.instance, assignment.player, {}});
  }
}

PadState readPlayer(const std::vector<FakeController>& controllers, int32_t player) {
  const auto match = std::find_if(controllers.begin(), controllers.end(), [player](const FakeController& controller) {
    return controller.player == player;
  });
  return match == controllers.end() ? PadState{} : match->state;
}

bool neutral(const PadState& state) {
  return state.buttons == 0 && state.stickX == 0 && state.stickY == 0 && state.cStickX == 0 &&
         state.cStickY == 0 && state.leftTrigger == 0 && state.rightTrigger == 0;
}

int32_t playerFor(const ControllerReconcilePlan& plan, uint32_t instance) {
  const auto assignment = std::find_if(plan.assign.begin(), plan.assign.end(), [instance](const auto& candidate) {
    return candidate.instance == instance;
  });
  return assignment == plan.assign.end() ? -2 : assignment->player;
}

} // namespace

int main() {
  const PadState held{0x0120, 96, -80, -72, 64, 255, 192};

  // A missed removal event must close stale player 1 and release held inputs.
  std::vector<FakeController> runtime{{101, 0, held}};
  auto plan = plan_controller_reconciliation({ControllerSnapshot{101, 0, false}}, {}, 4);
  assert(plan.close == std::vector<uint32_t>{101});
  assert(plan.open.empty());
  applyPlan(runtime, plan);
  assert(runtime.empty());
  assert(neutral(readPlayer(runtime, 0)));

  // The sole returning controller reclaims player 1 (zero-based slot 0).
  plan = plan_controller_reconciliation({}, {202}, 4);
  assert(plan.close.empty());
  assert(plan.open == std::vector<uint32_t>{202});
  assert(playerFor(plan, 202) == 0);

  // A genuinely additional controller takes player 2 without moving player 1.
  plan = plan_controller_reconciliation({ControllerSnapshot{202, 0, true}}, {202, 303}, 4);
  assert(plan.close.empty());
  assert(plan.open == std::vector<uint32_t>{303});
  assert(playerFor(plan, 303) == 1);

  // Reconciliation preserves two valid controller owners exactly.
  plan = plan_controller_reconciliation(
      {ControllerSnapshot{202, 0, true}, ControllerSnapshot{303, 1, true}}, {202, 303}, 4);
  assert(plan.close.empty());
  assert(plan.open.empty());
  assert(plan.assign.empty());

  // Replacing only player 2 keeps player 1 and reuses the freed slot.
  plan = plan_controller_reconciliation(
      {ControllerSnapshot{202, 0, true}, ControllerSnapshot{303, 1, false}}, {202, 404}, 4);
  assert(plan.close == std::vector<uint32_t>{303});
  assert(plan.open == std::vector<uint32_t>{404});
  assert(playerFor(plan, 404) == 1);

  // Foreground reconciliation handles a missed sleep/removal plus the returning identity.
  plan = plan_controller_reconciliation({ControllerSnapshot{202, 0, false}}, {505}, 4);
  assert(plan.close == std::vector<uint32_t>{202});
  assert(plan.open == std::vector<uint32_t>{505});
  assert(playerFor(plan, 505) == 0);

  return 0;
}
