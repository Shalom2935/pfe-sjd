# FaultSim

Scripts MATLAB pour preparer et executer les scenarios de simulation.

```matlab
cd('<repo>/model/FullLoop_DIAM4100/FaultSim')
FaultSim_prepareModel('ForceRebuild', true, 'Mode', 'smoke')
FaultSim_runBatch('Mode', 'smoke', 'RebuildModel', false)
```
