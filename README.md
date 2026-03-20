# AnniversaryTower

**Version:** 1.29
**Platform:** MacroQuest (MQNext) + Lua
**Author:** You (maintained / extended)

---

## Overview

`AnniversaryTower` automates:

* Anniversary Tower **missions**
* Anniversary Tower **key tasks**
* Travel between tower levels and zones
* Item collection, combines, and reward handling

It is designed for **fully automated group play** using MQ tools like:

* RGMercs
* KissAssist
* CWTN
* MQ2Boxr

---

## Features

### Missions

* Automatically requests, runs, and completes all tower missions
* Handles navigation, combat, and objective logic
* Supports all floors (2–13)

### Key Tasks

* Acquires key quests
* Collects required items
* Combines keys automatically
* Handles reward windows (auto-accept)

### Automation Integration

Supports:

* `rgmercs`
* `kissassist`
* `cwtn`
* `mq2boxr`

### Travel System

* Smart tower navigation
* Optional clicky usage:

  * North Ro port
  * PoK port
  * Gate AA
* Group synchronization

---

## Folder Structure

```
MQNext/
 └── lua/
     └── anniversarytower/
         ├── init.lua
         ├── engine.lua
         ├── key_tasks.lua
         ├── tower_travel.lua
         └── ...
```

### Config Location

```
C:\MQNext\Config\AnniversaryTower\
    AnniversaryTower_<Character>.ini
```

⚠️ The folder must exist or be created at runtime.

---

## First Run

1. Load MacroQuest
2. Run:

```
/lua run anniversarytower
```

3. The script will:

   * Initialize UI
   * Create config file
   * Scan achievements and keys

---

## Commands

### Main Command

```
/tower
```

### Usage

```
/tower mission <floor>
/tower key <floor>
```

### Examples

```
/tower mission 8
/tower key jungle
/tower mission dragons
```

---

## Configuration

Settings are stored per-character:

```
AnniversaryTower_<Character>.ini
```

### Key Sections

#### General

```ini
[general]
MessagingType=dannet
UseMageCoth=true
UseNroPortClicky=true
UsePoKPortClicky=true
UseGateSpell=true
```

#### Missions

```ini
[missions]
frost_UseLevitation=false
steam_UseLevitation=false
jungle_KillBarrels=true
```

#### Key Tasks

```ini
[key_tasks]
returnToTowerWhenDone=true
getAllTasksUpFront=true
```

#### Automation

```ini
[automation]
rgmercs=true
kissassist=false
cwtn=false
boxr=false
```

---

## Known Behavior

### Combine System

* Uses `/itemnotify packX rightmouseup`
* Waits for `PackX` window open state
* Inserts items into container
* Executes combine
* Attempts reward collection

### Reward Handling

* Uses:

```
/notify RewardSelectionWnd RewardSelectionChooseButton leftmouseup
```

* Falls back to:

  * Cursor cleanup
  * Inventory recovery

---

## Known Issues

### 1. Reward Window Stacking

* Multiple reward windows may accumulate
* Happens when:

  * UI lag
  * missed detection timing

**Symptom:**

* Rewards pile up (10+ windows)

---

### 2. Pack Window Behavior

* Pack may:

  * open then immediately close
  * fail to register as open

**Cause:**

* UI interference (casting, plugins, lag)

---

### 3. Jungle Key Behavior

* If items already exist:

  * Script may still attempt travel
* Combine step may fail if pack not detected properly

---

### 4. External Interference

Plugins like:

* RGMercs spell memming
* Navigation interruptions

can break timing-sensitive steps like:

* combine
* reward acceptance

---

## Troubleshooting

### Config Errors

**Error:**

```
Error loading file ... AnniversaryTower_<name>.ini
```

**Fix:**
Create folder manually:

```
C:\MQNext\Config\AnniversaryTower
```

---

### Combine Fails

Check:

* Container is in top-level inventory
* Pack window is not blocked
* No casting / memming during combine

---

### Rewards Not Collected

Manually test:

```
/notify RewardSelectionWnd RewardSelectionChooseButton leftmouseup
```

If that works:
→ timing issue in script

---

## Development Notes

* Uses `mq.TLO` heavily for state checks

* UI detection relies on:

  * `Window('PackX').Open()`
  * `Window('RewardSelectionWnd').Open()`

* Timing-sensitive sections:

  * Combine
  * Reward selection
  * Navigation transitions

---

## Recommendations

* Avoid heavy casting during combines
* Keep inventory organized
* Ensure containers are in top-level slots
* Use consistent automation framework (don’t mix systems heavily)

---

## Future Improvements

* Reliable reward queue handling
* Event-driven combine detection
* Better UI state validation
* Reduced retry spam
* Safer pack opening logic

---

## Summary

`AnniversaryTower` is a full automation system for EQ Anniversary Tower content.

It works well when:

* UI is stable
* plugins are not interfering
* timing is respected

Most issues are **timing/UI detection related**, not logic errors.

---

## License

Personal use / modification.

---
