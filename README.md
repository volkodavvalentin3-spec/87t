# JMod EZ Workers (submod)

Hire real player-bots with **gold**, keep them running with **nutrients**, and put them to work:
mining with a **pickaxe**, **auto-crafting** at JMod workbenches (results scatter instead of clipping into each other),
hauling resources into crates.

Requires **JMod** (Jackarunda). Does not edit any JMod file.

## Install
Drop the `ez_workers` folder into `garrysmod/addons/`. The server needs a free player slot per worker
(bots are real players, so start a multiplayer game: `maxplayers 8` or more).

## Use
* Open the **C-menu** (context menu) and click the **EZ Workers** icon  - or type `!workers` / `ezw_menu`.
* **Hire**: stand within 250 units of some gold (floor, crate or your JMod inventory) -> pick a player model (or random) -> HIRE.
* **Feed**: drop nutrients within ~170 units of the worker. They eat automatically when energy < 40%.
* **Jobs**: Idle, Follow, Miner, Crafter, Hauler.

## ConVars (all replicated/archived)
| convar | default | meaning |
|---|---|---|
| ezw_hire_cost | 50 | gold per worker |
| ezw_max_per_player | 4 | worker limit per player |
| ezw_pay_range | 250 | how close gold must be |
| ezw_energy_drain | 0.6 | energy / second while working |
| ezw_nutrient_energy | 3 | energy per nutrient unit |
| ezw_carry_capacity | 100 | base carry capacity (grows with level) |
| ezw_craft_delay | 2.5 | seconds between crafts |
| ezw_scatter_crafts | 1 | scatter crafted items |
| ezw_scatter_force | 140 | scatter strength |
| ezw_teleport_when_stuck | 1 | teleport stuck workers toward their goal |

Admin commands: `ezw_hire_free [model] [name]`, `ezw_dismiss_all`.

## Notes
* Maps with a navmesh get real A* pathfinding. Maps without one fall back to straight-line walking, jumping and side-stepping.
* Workers added to the owner's JMod friend list (sentries will not shoot them).
