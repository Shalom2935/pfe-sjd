function [cfg, FullLoop, geo] = FaultSim_prepareModel(varargin)
%FAULTSIM_PREPAREMODEL Create and patch local fault-simulation model copy.
%
% Usage:
%   FaultSim_prepareModel('ForceRebuild', true)
%
% Output model:
%   AGL_FullLoop_DIAM4100_faultsim.slx
%
% The original AGL_FullLoop_DIAM4100.slx is not modified.

    parser = inputParser;
    parser.addParameter('ForceRebuild', false, @(x)islogical(x) && isscalar(x));
    parser.addParameter('Mode', 'full', @(s)ischar(s) || isstring(s));
    parser.addParameter('AcceptUnvalidatedRanges', false, @(x)islogical(x) && isscalar(x));
    parser.parse(varargin{:});

    cfg = FaultSim_config('Mode', parser.Results.Mode, ...
                          'AcceptUnvalidatedRanges', parser.Results.AcceptUnvalidatedRanges);

    localEnsureDirs(cfg);
    addpath(cfg.paths.fullLoopDir);
    addpath(cfg.paths.faultSimDir);

    if ~exist(cfg.model.originalFile, 'file')
        error('Original model not found: %s', cfg.model.originalFile);
    end

    if bdIsLoaded(cfg.model.faultName)
        close_system(cfg.model.faultName, 0);
    end

    rebuild = parser.Results.ForceRebuild || ~exist(cfg.model.faultFile, 'file');
    if rebuild
        copyfile(cfg.model.originalFile, cfg.model.faultFile, 'f');
    end

    % Load central full-loop parameters.
    run(fullfile(cfg.paths.fullLoopDir, 'FullLoop_simParams.m'));
    FullLoop = evalin('base', 'FullLoop');

    [FullLoop, geo] = localBuildOptionBGeometry(FullLoop, cfg);
    FullLoop.model.name = cfg.model.faultName;
    assignin('base', 'FullLoop', FullLoop);

    FaultSim = localDefaultFaultState(cfg, geo);
    assignin('base', 'FaultSim', FaultSim);

    save(fullfile(cfg.paths.metadataDir, 'FaultSim_geometry.mat'), 'cfg', 'FullLoop', 'geo', 'FaultSim');
    localWriteGeometryCsv(cfg, geo, FullLoop);

    load_system(cfg.model.faultFile);

    if rebuild
        localPatchFaultTopology(cfg, FullLoop, geo);
        save_system(cfg.model.faultName, cfg.model.faultFile);
    end

    set_param(cfg.model.faultName, ...
        'StopTime', 'FaultSim.simTime_s', ...
        'MaxStep', 'FaultSim.Ts_s', ...
        'ReturnWorkspaceOutputs', 'on');

    save_system(cfg.model.faultName, cfg.model.faultFile);

    fprintf('\n[OK] FaultSim model ready: %s\n', cfg.model.faultFile);
    fprintf('[OK] Fault nodes: %d, total length: %.3f m\n', geo.nodeCount, geo.totalLength_m);
    fprintf('[OK] Geometry metadata: %s\n\n', cfg.paths.metadataDir);
end

function localEnsureDirs(cfg)
    dirs = {cfg.paths.outputDir, cfg.paths.rawDir, cfg.paths.featureDir, cfg.paths.metadataDir, cfg.paths.logDir};
    for k = 1:numel(dirs)
        if ~exist(dirs{k}, 'dir')
            mkdir(dirs{k});
        end
    end
end

function [FullLoop, geo] = localBuildOptionBGeometry(FullLoop, cfg)
    leadIn_m = FullLoop.loop.rccToFirstRegard_m;
    leadOut_m = FullLoop.loop.rccToLastRegard_m;
    step_m = cfg.locationStep_m;

    leadInSegments = localSplitLongSpan(leadIn_m, step_m);
    interRegardSegments = FullLoop.loop.regardSpacing_m * ones(1, FullLoop.loop.equippedRegardCount - 1);
    leadOutSegments = localSplitLongSpan(leadOut_m, step_m);

    segLengths = [leadInSegments, interRegardSegments, leadOutSegments];
    nodeDistances = cumsum(segLengths);

    geo = struct();
    geo.segmentLengths_m = segLengths(:)';
    geo.segmentLengths_km = geo.segmentLengths_m / 1000;
    geo.nodeDistances_m = nodeDistances(:)';
    geo.nodeCount = numel(geo.nodeDistances_m);
    geo.segmentCount = numel(geo.segmentLengths_m);
    geo.totalLength_m = sum(geo.segmentLengths_m);
    geo.leadInSegmentCount = numel(leadInSegments);
    geo.interRegardSegmentCount = numel(interRegardSegments);
    geo.leadOutSegmentCount = numel(leadOutSegments);
    geo.siteNodeIndex = geo.leadInSegmentCount + (0:FullLoop.loop.equippedRegardCount-1);
    geo.siteDistance_m = geo.nodeDistances_m(geo.siteNodeIndex);

    if abs(geo.totalLength_m - FullLoop.loop.length_m) > 1e-6
        error('FaultSim geometry length mismatch: %.6f m vs %.6f m.', ...
            geo.totalLength_m, FullLoop.loop.length_m);
    end

    expectedSiteDistance = [FullLoop.loads.Distance_m];
    for site = 1:FullLoop.loop.equippedRegardCount
        idxLoad = find([FullLoop.loads.RegardIndex] == site, 1, 'first');
        if isempty(idxLoad)
            continue;
        end
        err = abs(geo.siteDistance_m(site) - FullLoop.loads(idxLoad).Distance_m);
        if err > 1e-6
            error('Regard %d distance mismatch: geometry %.6f m, load table %.6f m.', ...
                site, geo.siteDistance_m(site), FullLoop.loads(idxLoad).Distance_m);
        end
    end

    FullLoop.faultsim = struct();
    FullLoop.faultsim.segments.length_m = geo.segmentLengths_m;
    FullLoop.faultsim.segments.length_km = geo.segmentLengths_km;
    FullLoop.faultsim.segments.count = geo.segmentCount;
    FullLoop.faultsim.node.distance_m = geo.nodeDistances_m;
    FullLoop.faultsim.node.count = geo.nodeCount;
    FullLoop.faultsim.site.nodeIndex = geo.siteNodeIndex;
    FullLoop.faultsim.site.distance_m = geo.siteDistance_m;
end

function parts = localSplitLongSpan(length_m, step_m)
    nFull = floor(length_m / step_m);
    rem_m = length_m - nFull * step_m;
    parts = step_m * ones(1, nFull);
    if rem_m > 1e-9
        parts = [parts, rem_m];
    end
end

function FaultSim = localDefaultFaultState(cfg, geo)
    FaultSim = struct();
    FaultSim.fs_Hz = cfg.fs_Hz;
    FaultSim.Ts_s = cfg.Ts_s;
    FaultSim.simTime_s = cfg.simTime_s;
    FaultSim.featureWindow_s = cfg.featureWindow_s;
    FaultSim.nodeDistance_m = geo.nodeDistances_m;
    FaultSim.nodeCount = geo.nodeCount;
    FaultSim.shuntR_ohm = cfg.inactiveShuntR_ohm * ones(1, geo.nodeCount);
    FaultSim.shuntC_F = cfg.inactiveShuntC_F * ones(1, geo.nodeCount);
    FaultSim.seriesR_ohm = cfg.normalSeriesR_ohm * ones(1, geo.nodeCount);
    FaultSim.activeClassId = 0;
    FaultSim.activeClassName = 'HEALTHY';
    FaultSim.activeNodeIndex = NaN;
    FaultSim.activeDistance_m = NaN;
    FaultSim.activeSeverity = NaN;
end

function localWriteGeometryCsv(cfg, geo, FullLoop)
    nodeTable = table((1:geo.nodeCount)', geo.nodeDistances_m(:), ...
        'VariableNames', {'node_index','distance_m'});
    writetable(nodeTable, fullfile(cfg.paths.metadataDir, 'FaultSim_nodes.csv'));

    segmentTable = table((1:geo.segmentCount)', geo.segmentLengths_m(:), geo.nodeDistances_m(:), ...
        'VariableNames', {'segment_index','length_m','end_distance_m'});
    writetable(segmentTable, fullfile(cfg.paths.metadataDir, 'FaultSim_segments.csv'));

    loadRows = struct([]);
    for k = 1:numel(FullLoop.loads)
        loadRows(k).module_index = k; %#ok<AGROW>
        loadRows(k).name = string(FullLoop.loads(k).Name);
        loadRows(k).regard_index = FullLoop.loads(k).RegardIndex;
        loadRows(k).distance_m = FullLoop.loads(k).Distance_m;
        loadRows(k).node_index = localNearestNode(geo.nodeDistances_m, FullLoop.loads(k).Distance_m);
    end
    writetable(struct2table(loadRows), fullfile(cfg.paths.metadataDir, 'FaultSim_load_nodes.csv'));

    surgeRows = struct([]);
    for k = 1:numel(FullLoop.surge.distance_m)
        surgeRows(k).surge_index = k; %#ok<AGROW>
        surgeRows(k).regard_index = FullLoop.surge.regardIndex(k);
        surgeRows(k).distance_m = FullLoop.surge.distance_m(k);
        surgeRows(k).node_index = localNearestNode(geo.nodeDistances_m, FullLoop.surge.distance_m(k));
    end
    writetable(struct2table(surgeRows), fullfile(cfg.paths.metadataDir, 'FaultSim_surge_nodes.csv'));
end

function idx = localNearestNode(nodeDistances_m, distance_m)
    [~, idx] = min(abs(nodeDistances_m - distance_m));
end

function localPatchFaultTopology(cfg, FullLoop, geo)
    mdl = cfg.model.faultName;

    load_system('sps_lib');
    lib.seriesRLC = 'sps_lib/Passives/Series RLC Branch';
    lib.ground = 'sps_lib/Utilities/Ground';
    if getSimulinkBlockHandle(lib.seriesRLC) < 0
        error('Cannot find %s. Install/load Simscape Electrical Specialized Power Systems.', lib.seriesRLC);
    end
    if getSimulinkBlockHandle(lib.ground) < 0
        error('Cannot find %s. Install/load Simscape Electrical Specialized Power Systems.', lib.ground);
    end

    localDeleteRootLines(mdl);

    diamBlock = localFindExactRootBlock(mdl, 'Diam4100_CCR');
    diamPH = get_param(diamBlock, 'PortHandles');
    if numel(diamPH.RConn) < 2
        error('DIAM4100 block does not expose two RConn ports as expected.');
    end

    cableTemplate = [mdl '/Cable_001'];
    if ~ishandle(getSimulinkBlockHandle(cableTemplate))
        error('Cable_001 template not found in %s.', mdl);
    end

    % Remove previous generated fault blocks if any, but keep original cables
    % until new cable blocks have been copied from Cable_001.
    localDeleteBlocksByName(mdl, '^Cable_FS_\d+$');
    localDeleteBlocksByName(mdl, '^FAULT_.*$');

    % Prepare site-to-module mapping.
    siteModules = cell(1, FullLoop.loop.equippedRegardCount);
    for k = 1:numel(FullLoop.loads)
        siteModules{FullLoop.loads(k).RegardIndex}(end+1) = k; %#ok<AGROW>
    end

    measuredModules = [1 10 20 30 40 50 51];

    [currentPort, rccVoltageReturnPort] = localInsertRCCHeadExports(mdl, diamPH.RConn(1));
    segIdx = 0;

    % Lead-in from RCC to first equipped regard.
    for k = 1:geo.leadInSegmentCount
        [currentPort, segIdx] = localAddCableFaultNode(cfg, geo, lib, cableTemplate, currentPort, segIdx + 1);
    end

    % Equipped sites and inter-regard segments.
    for site = 1:FullLoop.loop.equippedRegardCount
        for moduleIdx = siteModules{site}
            if ismember(moduleIdx, measuredModules)
                [currentPort] = localInsertCurrentMeasurement(mdl, currentPort, moduleIdx);
            end
            [currentPort] = localInsertTIModule(mdl, FullLoop, currentPort, moduleIdx);
        end

        if site < FullLoop.loop.equippedRegardCount
            [currentPort, segIdx] = localAddCableFaultNode(cfg, geo, lib, cableTemplate, currentPort, segIdx + 1);
        end
    end

    % Return from last equipped regard to RCC.
    for k = 1:geo.leadOutSegmentCount
        [currentPort, segIdx] = localAddCableFaultNode(cfg, geo, lib, cableTemplate, currentPort, segIdx + 1);
    end

    if segIdx ~= geo.segmentCount
        error('Internal patch error: wired %d segments, expected %d.', segIdx, geo.segmentCount);
    end

    localConnect(mdl, currentPort, diamPH.RConn(2));
    localConnect(mdl, rccVoltageReturnPort, diamPH.RConn(2));

    % Original cable blocks are now disconnected. Delete them after cloning.
    localDeleteBlocksByName(mdl, '^Cable_\d{3}$');

    % Keep simulation outputs as To Workspace variables.
    set_param(mdl, 'ReturnWorkspaceOutputs', 'on');
end

function localDeleteRootLines(mdl)
    lines = find_system(mdl, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'line');
    for k = 1:numel(lines)
        try
            delete_line(lines(k));
        catch
        end
    end
end

function localDeleteBlocksByName(mdl, expr)
    blocks = find_system(mdl, 'SearchDepth', 1, 'RegExp', 'on', 'Name', expr);
    for k = 1:numel(blocks)
        try
            delete_block(blocks{k});
        catch
        end
    end
end

function block = localFindRootBlock(mdl, namePattern)
    candidates = find_system(mdl, 'SearchDepth', 1, 'RegExp', 'on', 'Name', ['.*' namePattern '.*']);
    candidates = candidates(~strcmp(candidates, mdl));
    if isempty(candidates)
        error('No root block matching %s found in %s.', namePattern, mdl);
    end
    block = candidates{1};
end

function block = localFindExactRootBlock(mdl, blockName)
    candidates = find_system(mdl, 'SearchDepth', 1, 'Name', blockName);
    candidates = candidates(~strcmp(candidates, mdl));
    if isempty(candidates)
        error('Root block not found: %s/%s.', mdl, blockName);
    end
    if numel(candidates) > 1
        error('Multiple root blocks named %s found in %s.', blockName, mdl);
    end
    block = candidates{1};
end

function [nextPort, segIdx] = localAddCableFaultNode(cfg, geo, lib, cableTemplate, currentPort, segIdx)
    mdl = cfg.model.faultName;
    [x, y] = localLayout(segIdx);

    cable = [mdl sprintf('/Cable_FS_%03d', segIdx)];
    add_block(cableTemplate, cable, 'MakeNameUnique', 'off');
    set_param(cable, 'Position', [x, y, x+90, y+45]);
    set_param(cable, 'Length', sprintf('FullLoop.faultsim.segments.length_km(%d)', segIdx));
    cablePH = get_param(cable, 'PortHandles');

    localConnect(mdl, currentPort, cablePH.LConn(1));
    nodePort = cablePH.RConn(1);

    % Resistive shunt to ground.
    rBlock = [mdl sprintf('/FAULT_R_%03d', segIdx)];
    rGround = [mdl sprintf('/FAULT_GND_R_%03d', segIdx)];
    add_block(lib.seriesRLC, rBlock, 'MakeNameUnique', 'off');
    add_block(lib.ground, rGround, 'MakeNameUnique', 'off');
    set_param(rBlock, 'Position', [x+105, y+70, x+175, y+110]);
    set_param(rGround, 'Position', [x+190, y+76, x+220, y+106]);
    set_param(rBlock, 'BranchType', 'R');
    set_param(rBlock, 'Resistance', sprintf('FaultSim.shuntR_ohm(%d)', segIdx));
    rPH = get_param(rBlock, 'PortHandles');
    localConnect(mdl, nodePort, rPH.LConn(1));
    localConnect(mdl, rPH.RConn(1), localFirstElectricalPort(rGround));

    % Capacitive shunt to ground.
    cBlock = [mdl sprintf('/FAULT_C_%03d', segIdx)];
    cGround = [mdl sprintf('/FAULT_GND_C_%03d', segIdx)];
    add_block(lib.seriesRLC, cBlock, 'MakeNameUnique', 'off');
    add_block(lib.ground, cGround, 'MakeNameUnique', 'off');
    set_param(cBlock, 'Position', [x+105, y+125, x+175, y+165]);
    set_param(cGround, 'Position', [x+190, y+131, x+220, y+161]);
    set_param(cBlock, 'BranchType', 'C');
    set_param(cBlock, 'Capacitance', sprintf('FaultSim.shuntC_F(%d)', segIdx));
    cPH = get_param(cBlock, 'PortHandles');
    localConnect(mdl, nodePort, cPH.LConn(1));
    localConnect(mdl, cPH.RConn(1), localFirstElectricalPort(cGround));

    % Series resistance used for open-circuit class.
    sBlock = [mdl sprintf('/FAULT_SERIES_%03d', segIdx)];
    add_block(lib.seriesRLC, sBlock, 'MakeNameUnique', 'off');
    set_param(sBlock, 'Position', [x+125, y, x+205, y+45]);
    set_param(sBlock, 'BranchType', 'R');
    set_param(sBlock, 'Resistance', sprintf('FaultSim.seriesR_ohm(%d)', segIdx));
    sPH = get_param(sBlock, 'PortHandles');
    localConnect(mdl, nodePort, sPH.LConn(1));
    nextPort = sPH.RConn(1);
end

function [x, y] = localLayout(index)
    x0 = 850;
    y0 = 60;
    dx = 245;
    dy = 230;
    wrap = 8;
    col = mod(index-1, wrap);
    row = floor((index-1) / wrap);
    x = x0 + col * dx;
    y = y0 + row * dy;
end

function [nextPort] = localInsertCurrentMeasurement(mdl, currentPort, moduleIdx)
    meas = [mdl sprintf('/I_MEAS_%03d', moduleIdx)];
    sink = [mdl sprintf('/ToWorkspace_I_MEAS_%03d', moduleIdx)];
    if ~ishandle(getSimulinkBlockHandle(meas))
        error('Missing current measurement block: %s', meas);
    end
    if ~ishandle(getSimulinkBlockHandle(sink))
        error('Missing ToWorkspace block: %s', sink);
    end
    measPH = get_param(meas, 'PortHandles');
    sinkPH = get_param(sink, 'PortHandles');
    localConnect(mdl, currentPort, measPH.LConn(1));
    localConnect(mdl, measPH.Outport(1), sinkPH.Inport(1));
    nextPort = measPH.RConn(1);
end

function [nextPort, voltageReturnPort] = localInsertRCCHeadExports(mdl, currentPort)
    currentMeas = localFindExactRootBlock(mdl, 'Current Measurement');
    voltageMeas = localFindExactRootBlock(mdl, 'RCC Voltage Measurement');
    iSink = localFindExactRootBlock(mdl, 'ToWorkspace_i_RCC');
    uSink = localFindExactRootBlock(mdl, 'ToWorkspace_u_RCC');

    iPH = get_param(currentMeas, 'PortHandles');
    uPH = get_param(voltageMeas, 'PortHandles');
    iSinkPH = get_param(iSink, 'PortHandles');
    uSinkPH = get_param(uSink, 'PortHandles');

    if numel(iPH.LConn) < 1 || numel(iPH.RConn) < 1 || numel(iPH.Outport) < 1
        error('RCC current measurement block has unexpected ports: %s.', currentMeas);
    end
    if numel(uPH.LConn) < 2 || numel(uPH.Outport) < 1
        error('RCC voltage measurement block has unexpected ports: %s.', voltageMeas);
    end

    localConnect(mdl, currentPort, iPH.LConn(1));
    localConnect(mdl, iPH.LConn(1), uPH.LConn(1));
    localConnect(mdl, iPH.Outport(1), iSinkPH.Inport(1));
    localConnect(mdl, uPH.Outport(1), uSinkPH.Inport(1));

    nextPort = iPH.RConn(1);
    voltageReturnPort = uPH.LConn(2);
end

function [nextPort] = localInsertTIModule(mdl, FullLoop, currentPort, moduleIdx)
    loadName = FullLoop.loads(moduleIdx).Name;
    ti = [mdl sprintf('/TI_%03d_%s', moduleIdx, loadName)];
    lamp = [mdl sprintf('/LOAD_%03d_%s', moduleIdx, loadName)];
    if ~ishandle(getSimulinkBlockHandle(ti))
        error('Missing TI block: %s', ti);
    end
    if ~ishandle(getSimulinkBlockHandle(lamp))
        error('Missing load block: %s', lamp);
    end

    set_param(ti, ...
        'NominalPower', sprintf('FullLoop.tiModules(%d).Pn_fn', moduleIdx), ...
        'Winding1', sprintf('FullLoop.tiModules(%d).W1', moduleIdx), ...
        'Winding2', sprintf('FullLoop.tiModules(%d).W2', moduleIdx), ...
        'Saturation', sprintf('FullLoop.tiModules(%d).Sat', moduleIdx), ...
        'CoreLoss', sprintf('FullLoop.tiModules(%d).Rm', moduleIdx));
    set_param(lamp, ...
        'BranchType', 'R', ...
        'Resistance', sprintf('FullLoop.loads(%d).SecondaryResistance_ohm', moduleIdx));

    tiPH = get_param(ti, 'PortHandles');
    lampPH = get_param(lamp, 'PortHandles');

    localConnect(mdl, currentPort, tiPH.LConn(1));
    localConnect(mdl, tiPH.RConn(1), lampPH.LConn(1));
    localConnect(mdl, lampPH.RConn(1), tiPH.RConn(2));
    nextPort = tiPH.LConn(2);
end

function ph = localFirstElectricalPort(block)
    ports = get_param(block, 'PortHandles');
    if isfield(ports, 'LConn') && ~isempty(ports.LConn)
        ph = ports.LConn(1); return;
    end
    if isfield(ports, 'RConn') && ~isempty(ports.RConn)
        ph = ports.RConn(1); return;
    end
    error('No electrical conserving port found for block %s.', block);
end

function localConnect(mdl, srcPort, dstPort)
    try
        add_line(mdl, srcPort, dstPort, 'autorouting', 'on');
    catch ME
        error('Failed to connect ports in %s: %s', mdl, ME.message);
    end
end
