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
FaultSim_runBatch('Mode', 'smoke')
```

Do not run the full campaign until the smoke run is fully validated.

## Simulation horizon

The current smoke configuration uses:

- `FaultSim.simTime_s = 0.35 s`
- `FaultSim.featureWindow_s = 0.20 s`
- `FaultSim.Ts_s = 1e-4 s`, equivalent to `10 kHz`

At `50 Hz`, a `0.35 s` simulation contains 17.5 electrical periods. The
feature extractor uses the last `0.20 s`, i.e. 10 periods, so the first
`0.15 s` acts as a settling margin before the steady-state harmonic and RMS
features are computed.

This is sufficient for smoke validation of the fault-injection topology and
for a first quasi-steady-state feature check. It is not yet a final campaign
assumption. Before a full dataset is generated, the same representative
scenarios should be compared at longer horizons, for example `0.35 s`,
`0.50 s`, and `0.75 s`, to confirm that the extracted features have converged
and are not biased by the initial transient or by the DIAM4100 control loop.
