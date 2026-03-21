# TowerMissions.lua

Automation script for handling Anniversary Tower key tasks using MacroQuest (MQ).

---

## Overview

`TowerMissions.lua` automates the process of:

* Acquiring key tasks
* Traveling to required zones
* Completing task objectives
* Combining key fragments into repaired keys
* Handling post-combine rewards
* Cleaning up inventory

It supports all tower key tasks and integrates with utility modules such as:

* `mq_utils`
* `lua_utils`
* `tower_travel`
* `logger`

---

## Features

### Task Automation

* Automatically acquires tasks if not already active
* Executes task steps sequentially
* Handles combat, looting, navigation, and interactions

### Combine Handling

* Moves key container to a top-level inventory slot
* Opens the correct pack reliably
* Adds required items into the container
* Executes combine
* Handles reward collection

### Reward Handling

* Detects `RewardSelectionWnd`
* Clicks reward button when present
* Falls back to cursor/inventory sweep
* Handles delayed reward window appearance

### Inventory Management

* Cleans up leftover items
* Moves items between inventory and packs
* Prevents cursor clutter

---

## Key Components

### `RunKeyTask(level)`

Main entry point for executing a key task.

Flow:

1. Acquire task
2. Move container to top-level slot
3. Travel to zone (if needed)
4. Execute task steps
5. Combine items
6. Collect reward
7. Return items

---

### `DoCombine(key_task_details)`

Handles combining key fragments.

Steps:

1. Find container
2. Determine pack slot
3. Open pack window
4. Add required items
5. Execute combine
6. Handle reward

---

### `EnsurePackWindowOpen(pack)`

Ensures the correct pack window is open.

Key behavior:

* Uses `/itemnotify packX rightmouseup`
* Verifies `mq.TLO.Window('PackX').Open()`
* Handles timing issues with polling
* Avoids unreliable name-based itemnotify

---

### `AcceptRewardSelection()`

Handles reward window interaction.

Improved behavior:

* Polls for reward window instead of single wait
* Clicks reward button immediately when detected
* Verifies window closes
* Falls back to cursor sweep if no window appears

---

## Important Fixes Implemented

### 1. Pack Opening Reliability

**Problem:**

* Pack required multiple attempts or failed to open

**Fix:**

* Use only:

  ```
  /itemnotify packX rightmouseup
  ```
* Removed name-based itemnotify (unreliable)
* Added state verification using:

  ```lua
  mq.TLO.Window('PackX').Open()
  ```

---

### 2. Reward Window Not Being Clicked

**Problem:**

* Rewards piled up (not collected)

**Cause:**

* Reward window appeared after detection window
* Script missed timing

**Fix:**

* Replaced single wait with polling loop
* Click happens as soon as window appears

---

### 3. False “No Reward Window” Logs

**Problem:**

* Misleading logs even when reward was collected

**Fix:**

* Logging adjusted to reflect fallback behavior
* Cursor sweep added as backup

---

### 4. Unnecessary Zone Travel

**Problem:**

* Script traveled to zone even when items already collected

**Fix:**

* Detect if:

  * All combine items are present
  * Task is already on final step
* Skip travel and go directly to combine

---

### 5. Combine Timing Stability

**Problem:**

* Combine attempted during unstable UI state

**Fix:**

* Added delays and inventory stabilization
* Ensured container is properly moved and settled

---

## Known Limitations

### External Interference

Other automation (e.g. RGMercs) may:

* Interrupt UI
* Close windows
* Delay actions

### Reward Window Variability

* Not all combines trigger `RewardSelectionWnd`
* Some rewards go directly to cursor/inventory

### UI Timing Sensitivity

* MQ + EQ UI is asynchronous
* Requires delays and polling

---

## Debugging Tips

### Check Pack Open State

```lua
mq.TLO.Window('Pack9').Open()
```

### Verify Reward Window

```lua
mq.TLO.Window('RewardSelectionWnd').Open()
```

### Manual Test Commands

```text
/itemnotify pack9 rightmouseup
/notify RewardSelectionWnd RewardSelectionChooseButton leftmouseup
```

---

## Best Practices

* Avoid excessive retry loops (fix state instead)
* Always verify UI state after actions
* Prefer polling over fixed delays
* Do not rely solely on UI windows for success
* Validate results via inventory when possible

---

## Summary

This script automates the full lifecycle of tower key tasks, including:

* Task acquisition
* Objective execution
* Reliable combining
* Robust reward handling

Recent fixes significantly improved:

* Pack opening reliability
* Reward collection accuracy
* Task flow efficiency

---

## Future Improvements

* Direct validation of repaired key after combine
* Better handling of external script interference
* UI abstraction for different layouts
* Event-based detection instead of polling

---

## Author Notes

This script evolved through debugging real-world edge cases involving:

* MQ timing behavior
* EverQuest UI quirks
* Interaction with other automation systems

It prioritizes reliability over minimalism and includes safeguards for inconsistent UI behavior.

---

