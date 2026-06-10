# FaultSim local notes

This folder contains the local fault-simulation preparation scripts extracted
from `FaultSim_Local_Implementation_Guide.md`.

## Local adaptation

In the current healthy loop model, `u_RCC` and `i_RCC` are exported at the
root level of `AGL_FullLoop_DIAM4100.slx`, outside the `Diam4100_CCR`
subsystem. This is valid and intentional.

The guide's preparation script deletes root-level lines before rebuilding the
loop, so `FaultSim_prepareModel.m` has been adapted to reconnect the existing
root-level blocks:

- `Current Measurement`
- `RCC Voltage Measurement`
- `ToWorkspace_i_RCC`
- `ToWorkspace_u_RCC`

The nominal model is not modified by FaultSim. The generated model is:

```text
../AGL_FullLoop_DIAM4100_faultsim.slx
```

## MATLAB sequence

Run from MATLAB:

```matlab
cd('C:\Users\KSSS\Documents\Claude\Projects\Projet Fin d''Etude (PFE)\model\FullLoop_DIAM4100\FaultSim')
FaultSim_prepareModel('ForceRebuild', true, 'Mode', 'smoke')
FaultSim_runBatch('Mode', 'smoke', 'OverwriteExisting', true)
```

Do not run the full campaign until the smoke run is fully validated.
Use `OverwriteExisting=true` when revalidating the smoke set after a schema or
feature change; otherwise existing raw `.mat` files are skipped by design.

## Output isolation

Raw simulation files are separated by campaign mode:

```text
../outputs/FaultSim/raw/smoke/scenario_*.mat
../outputs/FaultSim/raw/full/scenario_*.mat
```

This prevents a full campaign from skipping scenarios whose numeric
`scenario_id` already exists from a smoke run. Features, logs and
range-specific scenario tables are tagged by mode and by scenario range, for
example:

```text
../outputs/FaultSim/features/FaultSim_features_full_000001_005000_plage_1.csv
../outputs/FaultSim/logs/FaultSim_runlog_full_000001_005000_plage_1.csv
../outputs/FaultSim/metadata/FaultSim_scenarios_full_000001_005000_plage_1.csv
```

## Electrical labels

The scenario table and extracted features include both the physical class
(`class_name`) and the measurable electrical family
(`electrical_fault_family`). This distinction is intentional: several
physical faults are electrically equivalent from the RCC head-end when only
`u_RCC(t)` and `i_RCC(t)` are observed.

| Physical class | Electrical family |
| --- | --- |
| `HEALTHY` | `healthy` |
| `HUMIDITY_PROGRESSIVE` | `high_R_resistive_leakage` |
| `TI_INSULATION_LEAKAGE` | `high_R_resistive_leakage` |
| `EARTH_SHORT` | `low_R_earth_fault` |
| `SURGE_ARRESTER_SHORT` | `low_R_earth_fault` |
| `REACTIVE_INCIPIENT` | `capacitive_leakage` |
| `OPEN_CIRCUIT` | `series_open` |
| `TI_LOAD_FAULT` | `secondary_load_fault` |

For ML validation, train and report the directly measurable target
`electrical_fault_family` plus fault distance first. The final physical class
should be inferred afterward from the known topology, for example by checking
whether a low-resistance earth fault distance coincides with a surge arrester
location.

## Simulation horizon

The current campaign configuration uses:

- `FaultSim.simTime_s = 1.10 s`
- `FaultSim.rawSaveWindow_s = 0.10 s`
- `FaultSim.featureWindow_s = 0.10 s`
- `FaultSim.Ts_s = 1e-4 s`, equivalent to `10 kHz`
- `cfg.execution.simulationMode = 'normal'`

At `50 Hz`, a period is `0.02 s`, so the final `0.10 s` window contains five
electrical periods and exactly 1000 samples at 10 kHz. The longer `1.10 s`
horizon leaves the DIAM4100 current controller enough time to settle before
the raw traces and features are extracted. Only the final stable raw window is
saved to limit disk usage during the full campaign.

## Scenario ranges

Use `StartAt`, `EndAt` and `RunTag` to run an identified subset of the full
scenario table:

```matlab
FaultSim_runBatch('Mode','full','AcceptUnvalidatedRanges',true, ...
    'RebuildModel',false,'StartAt',1,'EndAt',5000,'RunTag','plage_1')
```

`MaxScenarios` remains available and is now applied after `StartAt`, so
`StartAt=5001, MaxScenarios=5000` runs scenarios `5001:10000`.
