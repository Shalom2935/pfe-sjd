function FaultSim_runBatch(varargin)
%FAULTSIM_RUNBATCH Run smoke or full fault-simulation batch.
%
% Usage:
%   FaultSim_runBatch('Mode','smoke')
%   FaultSim_runBatch('Mode','full','AcceptUnvalidatedRanges',true)
%   FaultSim_runBatch('Mode','full','AcceptUnvalidatedRanges',true,'StartAt',1,'EndAt',5000,'RunTag','PC01')
%   FaultSim_runBatch('Mode','full','AcceptUnvalidatedRanges',true,'StartAt',5001,'EndAt',10000,'RunTag','PC02')
%   FaultSim_runBatch('Mode','full','AcceptUnvalidatedRanges',true,'StartAt',10001,'EndAt','end','RunTag','PC03')

    parser = inputParser;
    parser.addParameter('Mode', 'smoke', @(s)ischar(s) || isstring(s));
    parser.addParameter('AcceptUnvalidatedRanges', false, @(x)islogical(x) && isscalar(x));
    parser.addParameter('RebuildModel', false, @(x)islogical(x) && isscalar(x));
    parser.addParameter('StartAt', 1, @(x)isnumeric(x) && isscalar(x) && x >= 1);
    parser.addParameter('EndAt', inf, @(x)(isnumeric(x) && isscalar(x)) || ischar(x) || isstring(x));
    parser.addParameter('MaxScenarios', inf, @(x)isnumeric(x) && isscalar(x) && x >= 0);
    parser.addParameter('RunTag', '', @(s)ischar(s) || isstring(s));
    parser.addParameter('OverwriteExisting', false, @(x)islogical(x) && isscalar(x));
    parser.parse(varargin{:});

    mode = lower(char(parser.Results.Mode));
    cfg = FaultSim_config('Mode', mode, ...
                          'AcceptUnvalidatedRanges', parser.Results.AcceptUnvalidatedRanges);

    addpath(cfg.paths.fullLoopDir);
    addpath(cfg.paths.faultSimDir);
    localEnsureDirs(cfg);

    if parser.Results.RebuildModel || ~exist(cfg.model.faultFile, 'file') || ...
            ~exist(fullfile(cfg.paths.metadataDir, 'FaultSim_geometry.mat'), 'file')
        FaultSim_prepareModel('ForceRebuild', true, 'Mode', mode, ...
                              'AcceptUnvalidatedRanges', parser.Results.AcceptUnvalidatedRanges);
    else
        FaultSim_prepareModel('ForceRebuild', false, 'Mode', mode, ...
                              'AcceptUnvalidatedRanges', parser.Results.AcceptUnvalidatedRanges);
    end

    scenarios = FaultSim_buildScenarioTable('Mode', mode, ...
                                            'AcceptUnvalidatedRanges', parser.Results.AcceptUnvalidatedRanges);

    if strcmp(mode, 'smoke') && height(scenarios) > cfg.smoke.maxScenarios
        scenarios = scenarios(1:cfg.smoke.maxScenarios, :);
    end

    totalScenarios = height(scenarios);
    [startAt, endAt, rangeTag] = localResolveRunRange( ...
        totalScenarios, ...
        parser.Results.StartAt, ...
        parser.Results.EndAt, ...
        parser.Results.MaxScenarios);
    scenariosToRun = scenarios(startAt:endAt, :);

    geometryFile = fullfile(cfg.paths.metadataDir, 'FaultSim_geometry.mat');
    S = load(geometryFile, 'FullLoop', 'geo', 'FaultSim');
    FullLoop = S.FullLoop;
    FaultSimBase = S.FaultSim;

    load_system(cfg.model.faultFile);

    outTag = localBuildOutputTag(mode, rangeTag, parser.Results.RunTag);
    featureFile = fullfile(cfg.paths.featureDir, sprintf('FaultSim_features_%s.csv', outTag));
    logFile = fullfile(cfg.paths.logDir, sprintf('FaultSim_runlog_%s.csv', outTag));
    rangeScenarioFile = fullfile(cfg.paths.metadataDir, sprintf('FaultSim_scenarios_%s.csv', outTag));
    writetable(scenariosToRun, rangeScenarioFile);
    overwriteExisting = parser.Results.OverwriteExisting;

    if overwriteExisting
        localDeleteIfExists(featureFile);
        localDeleteIfExists(logFile);
    end

    fprintf('\nFaultSim batch mode: %s\n', mode);
    runCount = height(scenariosToRun);
    fprintf('Scenario table total: %d\n', totalScenarios);
    fprintf('Scenarios to run now: %d (rows %d:%d)\n', runCount, startAt, endAt);
    fprintf('Range scenario file: %s\n', rangeScenarioFile);
    fprintf('Raw output: %s\n', cfg.paths.rawDir);
    fprintf('Features: %s\n', featureFile);
    fprintf('Log: %s\n\n', logFile);
    if overwriteExisting
        fprintf('OverwriteExisting: true (existing raw files for selected scenarios will be replaced)\n\n');
    end

    for rowIdx = 1:height(scenariosToRun)
        sc = scenariosToRun(rowIdx, :);
        rawFile = fullfile(cfg.paths.rawDir, sprintf('scenario_%06d.mat', sc.scenario_id));

        if exist(rawFile, 'file')
            if overwriteExisting
                delete(rawFile);
            else
                fprintf('[SKIP] scenario %06d already exists.\n', sc.scenario_id);
                continue;
            end
        end

        tStart = tic;
        try
            fprintf('[RUN ] %06d | %s | %s | d=%.3f m | B=%s\n', ...
                sc.scenario_id, sc.class_name{1}, sc.fault_location_type{1}, ...
                sc.fault_distance_m, sc.brightness_label{1});

            % Refresh DIAM4100 workspace for requested brightness.
            assignin('base', 'FullLoop', FullLoop);
            FullLoop_prepareDIAM4100('ActiveBrightness', sc.brightness_index);
            DIAM4100 = evalin('base', 'DIAM4100');

            FS = localApplyScenarioToFaultState(FaultSimBase, cfg, sc);
            assignin('base', 'FaultSim', FS);
            assignin('base', 'DIAM4100', DIAM4100);

            simIn = Simulink.SimulationInput(cfg.model.faultName);
            simIn = simIn.setVariable('FullLoop', FullLoop);
            simIn = simIn.setVariable('DIAM4100', DIAM4100);
            simIn = simIn.setVariable('FaultSim', FS);
            simIn = simIn.setModelParameter('StopTime', 'FaultSim.simTime_s', ...
                                            'MaxStep', 'FaultSim.Ts_s', ...
                                            'ReturnWorkspaceOutputs', 'on', ...
                                            'SimulationMode', cfg.execution.simulationMode);
            simIn = localApplyLoadBlockParameters(simIn, cfg, FullLoop, sc);

            simOut = sim(simIn);
            raw = localCollectAndResampleSignals(simOut, cfg);
            features = localExtractFeatures(raw, cfg, sc, FS, DIAM4100);

            metadata = table2struct(sc);
            metadata.elapsed_s = toc(tStart);
            metadata.model_file = cfg.model.faultFile;
            metadata.fs_Hz = cfg.fs_Hz;
            metadata.simTime_s = cfg.simTime_s;
            metadata.rawSaveWindow_s = cfg.rawSaveWindow_s;
            metadata.featureWindow_s = cfg.featureWindow_s;
            metadata.savedWindowStart_s = raw.time_s(1);
            metadata.savedWindowEnd_s = raw.time_s(end);

            save(rawFile, 'raw', 'features', 'metadata', '-v7.3');
            localAppendTable(struct2table(features), featureFile);
            localAppendLog(logFile, sc, 'OK', '', metadata.elapsed_s);

            fprintf('[ OK ] %06d elapsed %.2f s\n', sc.scenario_id, metadata.elapsed_s);
        catch ME
            elapsed = toc(tStart);
            report = localErrorReport(ME);
            errorFile = localWriteErrorReport(cfg, mode, sc, report);
            message = sprintf('%s | detailed_report=%s', localSingleLine(ME.message), errorFile);
            localAppendLog(logFile, sc, 'ERROR', message, elapsed);
            fprintf(2, '\n[ERROR REPORT] scenario %06d\n%s\n', sc.scenario_id, report);
            warning('[FAIL] scenario %06d failed after %.2f s: %s', sc.scenario_id, elapsed, ME.message);
        end
    end

    fprintf('\n[END] FaultSim batch finished.\n');
end

function localEnsureDirs(cfg)
    dirs = {cfg.paths.outputDir, cfg.paths.rawDir, cfg.paths.featureDir, cfg.paths.metadataDir, cfg.paths.logDir};
    for k = 1:numel(dirs)
        if ~exist(dirs{k}, 'dir')
            mkdir(dirs{k});
        end
    end
end

function localDeleteIfExists(filePath)
    if exist(filePath, 'file')
        delete(filePath);
    end
end

function [startAt, endAt, rangeTag] = localResolveRunRange(totalScenarios, startAtArg, endAtArg, maxScenarios)
    startAt = floor(double(startAtArg));

    if startAt < 1
        error('StartAt must be >= 1.');
    end
    if startAt > totalScenarios
        error('StartAt=%d exceeds scenario count %d.', startAt, totalScenarios);
    end

    endAt = localParseEndAt(endAtArg, totalScenarios);

    if isfinite(maxScenarios)
        endAt = min(endAt, startAt + floor(double(maxScenarios)) - 1);
    end

    if endAt > totalScenarios
        warning('EndAt=%d exceeds scenario count %d. Clamping to end.', endAt, totalScenarios);
        endAt = totalScenarios;
    end

    if endAt < startAt
        error('Invalid run range: StartAt=%d, EndAt=%d.', startAt, endAt);
    end

    rangeTag = sprintf('%06d_%06d', startAt, endAt);
end

function endAt = localParseEndAt(endAtArg, totalScenarios)
    if ischar(endAtArg) || isstring(endAtArg)
        token = lower(strtrim(char(endAtArg)));
        if strcmp(token, 'end') || strcmp(token, 'inf') || strcmp(token, 'infinity')
            endAt = totalScenarios;
            return;
        end

        value = str2double(token);
        if isnan(value)
            error('EndAt must be numeric or ''end''. Got: %s', token);
        end
        endAt = floor(value);
        return;
    end

    if isinf(endAtArg)
        endAt = totalScenarios;
    else
        endAt = floor(double(endAtArg));
    end
end

function outTag = localBuildOutputTag(mode, rangeTag, runTag)
    outTag = sprintf('%s_%s', lower(char(mode)), rangeTag);

    runTag = strtrim(char(runTag));
    if ~isempty(runTag)
        runTag = regexprep(runTag, '[^A-Za-z0-9_-]', '_');
        outTag = sprintf('%s_%s', outTag, runTag);
    end
end

function FS = localApplyScenarioToFaultState(baseFS, cfg, sc)
    FS = baseFS;
    FS.shuntR_ohm(:) = cfg.inactiveShuntR_ohm;
    FS.shuntC_F(:) = cfg.inactiveShuntC_F;
    FS.seriesR_ohm(:) = cfg.normalSeriesR_ohm;
    FS.activeClassId = sc.class_id;
    FS.activeClassName = sc.class_name{1};
    FS.activeElectricalFaultFamily = sc.electrical_fault_family{1};
    FS.activeNodeIndex = sc.node_index;
    FS.activeDistance_m = sc.fault_distance_m;

    node = sc.node_index;
    if isnan(node)
        return;
    end

    switch sc.class_name{1}
        case {'HUMIDITY_PROGRESSIVE', 'EARTH_SHORT', 'SURGE_ARRESTER_SHORT', 'TI_INSULATION_LEAKAGE'}
            FS.shuntR_ohm(node) = sc.fault_R_ohm;
        case 'REACTIVE_INCIPIENT'
            FS.shuntC_F(node) = sc.fault_C_F;
        case 'OPEN_CIRCUIT'
            FS.seriesR_ohm(node) = sc.fault_R_ohm;
        case {'HEALTHY', 'TI_LOAD_FAULT'}
            % No primary-loop shunt/series activation here.
        otherwise
            error('Unknown class: %s', sc.class_name{1});
    end
end

function simIn = localApplyLoadBlockParameters(simIn, cfg, FullLoop, sc)
    mdl = cfg.model.faultName;

    % Reset all loads to nominal expression for every scenario.
    for k = 1:numel(FullLoop.loads)
        block = sprintf('%s/LOAD_%03d_%s', mdl, k, FullLoop.loads(k).Name);
        simIn = simIn.setBlockParameter(block, 'Resistance', ...
            sprintf('FullLoop.loads(%d).SecondaryResistance_ohm', k));
    end

    if strcmp(sc.class_name{1}, 'TI_LOAD_FAULT')
        moduleIdx = sc.fault_module_index;
        if isnan(moduleIdx) || moduleIdx < 1 || moduleIdx > numel(FullLoop.loads)
            error('Invalid module index for TI_LOAD_FAULT.');
        end
        block = sprintf('%s/LOAD_%03d_%s', mdl, moduleIdx, FullLoop.loads(moduleIdx).Name);
        switch sc.load_fault_mode{1}
            case 'open'
                simIn = simIn.setBlockParameter(block, 'Resistance', num2str(cfg.loadOpenR_ohm, 16));
            case 'short'
                simIn = simIn.setBlockParameter(block, 'Resistance', num2str(cfg.loadShortR_ohm, 16));
            otherwise
                error('Unsupported load_fault_mode: %s', sc.load_fault_mode{1});
        end
    end
end

function raw = localCollectAndResampleSignals(simOut, cfg)
    names = [cfg.signals.required, cfg.signals.optional];
    available = simOut.who;

    for k = 1:numel(cfg.signals.required)
        if ~ismember(cfg.signals.required{k}, available)
            error('Required signal %s not found in SimulationOutput.', cfg.signals.required{k});
        end
    end

    [tU, u] = localTimeseriesToVector(simOut.get('u_RCC'));
    [tI, i] = localTimeseriesToVector(simOut.get('i_RCC'));

    tAvailable0 = max([min(tU), min(tI), 0]);
    tAvailable1 = min([max(tU), max(tI), cfg.simTime_s]);

    if tAvailable1 <= tAvailable0
        error('Invalid simulation time interval: [%.6f, %.6f].', tAvailable0, tAvailable1);
    end

    if isfield(cfg, 'rawSaveWindow_s') && isfinite(cfg.rawSaveWindow_s) && cfg.rawSaveWindow_s > 0
        if cfg.rawSaveWindow_s + eps < cfg.featureWindow_s
            error('rawSaveWindow_s must be >= featureWindow_s.');
        end
        t0 = max(tAvailable0, tAvailable1 - cfg.rawSaveWindow_s);
    else
        t0 = tAvailable0;
    end

    t1 = tAvailable1;

    % Use exactly N samples at fs. This avoids the 1001-sample issue when
    % using t0:Ts:t1 on a 0.10 s window. With fs=10 kHz and 0.10 s, this
    % gives exactly 1000 samples, coherent with 5 cycles at 50 Hz.
    nSamples = floor((t1 - t0) / cfg.Ts_s);
    if nSamples < 8
        error('Selected raw window is too short: %.6f s.', t1 - t0);
    end

    t = t0 + (0:nSamples-1).' * cfg.Ts_s;

    raw = struct();
    raw.time_s = t;
    raw.u_RCC_V = interp1(tU, u, t, 'linear', 'extrap');
    raw.i_RCC_A = interp1(tI, i, t, 'linear', 'extrap');
    raw.savedWindowStart_s = t(1);
    raw.savedWindowEnd_s = t(end);
    raw.savedWindowDuration_s = nSamples * cfg.Ts_s;

    for k = 1:numel(names)
        name = names{k};
        if ismember(name, {'u_RCC','i_RCC'})
            continue;
        end
        if ismember(name, available)
            try
                [tx, x] = localTimeseriesToVector(simOut.get(name));
                raw.(matlab.lang.makeValidName(name)) = interp1(tx, x, t, 'linear', 'extrap');
            catch
                % Optional debug signals must not kill the simulation.
            end
        end
    end
end

function [t, y] = localTimeseriesToVector(x)
    if isa(x, 'timeseries')
        t = x.Time(:);
        y = squeeze(x.Data);
        y = y(:);
        return;
    end
    if isa(x, 'Simulink.SimulationData.Signal')
        [t, y] = localTimeseriesToVector(x.Values);
        return;
    end
    if isstruct(x) && isfield(x, 'time') && isfield(x, 'signals')
        t = x.time(:);
        y = squeeze(x.signals.values);
        y = y(:);
        return;
    end
    error('Unsupported signal format: %s', class(x));
end

function features = localExtractFeatures(raw, cfg, sc, ~, DIAM4100)
    t = raw.time_s;
    u = raw.u_RCC_V;
    i = raw.i_RCC_A;

    idx = t >= (t(end) - cfg.featureWindow_s);
    tw = t(idx);
    uw = u(idx);
    iw = i(idx);

    features = struct();
    features.scenario_id = sc.scenario_id;
    features.class_id = sc.class_id;
    features.class_name = string(sc.class_name{1});
    features.fault_group = string(sc.fault_group{1});
    features.electrical_fault_family = string(sc.electrical_fault_family{1});
    features.fault_location_type = string(sc.fault_location_type{1});
    features.fault_distance_m = sc.fault_distance_m;
    features.node_index = sc.node_index;
    features.fault_regard_index = sc.fault_regard_index;
    features.fault_module_index = sc.fault_module_index;
    features.fault_R_ohm = sc.fault_R_ohm;
    features.fault_C_F = sc.fault_C_F;
    features.load_fault_mode = string(sc.load_fault_mode{1});
    features.brightness_index = sc.brightness_index;
    features.brightness_label = string(sc.brightness_label{1});
    features.Iref_Arms = DIAM4100.control.Iref_Arms;

    features.U_RMS = sqrt(mean(uw.^2));
    features.I_RMS = sqrt(mean(iw.^2));
    features.U_peak = max(abs(uw));
    features.I_peak = max(abs(iw));
    features.U_crest = features.U_peak / max(features.U_RMS, eps);
    features.I_crest = features.I_peak / max(features.I_RMS, eps);
    features.U_mean = mean(uw);
    features.I_mean = mean(iw);
    features.U_std = std(uw);
    features.I_std = std(iw);

    specU = localHarmonicSpectrum(tw, uw, cfg.gridFrequency_Hz, cfg.features.harmonics);
    specI = localHarmonicSpectrum(tw, iw, cfg.gridFrequency_Hz, cfg.features.harmonics);

    for h = cfg.features.harmonics
        key = sprintf('H%d', h);
        features.(['U_' key '_amp']) = specU.amp(h);
        features.(['U_' key '_phase']) = specU.phase(h);
        features.(['I_' key '_amp']) = specI.amp(h);
        features.(['I_' key '_phase']) = specI.phase(h);

        z = specU.complex(h) / max(specI.complex(h), eps);
        features.(['Z_' key '_abs']) = abs(z);
        features.(['Z_' key '_angle']) = angle(z);
    end

    hList = cfg.features.harmonics;
    hNoFund = hList(hList ~= 1);
    features.THD_U = sqrt(sum(arrayfun(@(h)specU.amp(h).^2, hNoFund))) / max(specU.amp(1), eps);
    features.THD_I = sqrt(sum(arrayfun(@(h)specI.amp(h).^2, hNoFund))) / max(specI.amp(1), eps);
end

function spec = localHarmonicSpectrum(t, x, f0, harmonics)
    x = x(:);
    t = t(:);
    fs = 1 / median(diff(t));
    n = numel(x);
    if n < 8
        error('Not enough samples for FFT.');
    end

    x = x - mean(x);
    w = 0.5 - 0.5*cos(2*pi*(0:n-1)'/(n-1));
    X = fft(x .* w);
    scale = sum(w);

    spec.amp = containers.Map('KeyType','double','ValueType','double');
    spec.phase = containers.Map('KeyType','double','ValueType','double');
    spec.complex = containers.Map('KeyType','double','ValueType','any');

    for h = harmonics
        f = h * f0;
        idx = round(f / fs * n) + 1;
        idx = max(1, min(idx, n));
        value = 2 * X(idx) / scale;
        spec.amp(h) = abs(value);
        spec.phase(h) = angle(value);
        spec.complex(h) = value;
    end
end

function filePath = localWriteErrorReport(cfg, mode, sc, report)
    if ~exist(cfg.paths.logDir, 'dir')
        mkdir(cfg.paths.logDir);
    end
    filePath = fullfile(cfg.paths.logDir, ...
        sprintf('FaultSim_error_%s_%06d.txt', mode, sc.scenario_id));
    fid = fopen(filePath, 'w');
    if fid < 0
        error('Cannot write error report: %s', filePath);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', report);
end

function text = localSingleLine(text)
    text = regexprep(char(text), '\s+', ' ');
end

function report = localErrorReport(ME)
    try
        report = getReport(ME, 'extended', 'hyperlinks', 'off');
    catch
        report = ME.message;
    end

    if ~isempty(ME.cause)
        causeReports = strings(1, numel(ME.cause));
        for k = 1:numel(ME.cause)
            causeReports(k) = sprintf('Cause %d:\n%s', k, localErrorReport(ME.cause{k}));
        end
        report = sprintf('%s\n\n%s', report, strjoin(causeReports, newline));
    end
end

function localAppendTable(T, filePath)
    if exist(filePath, 'file')
        writetable(T, filePath, 'WriteMode', 'append', 'WriteVariableNames', false);
    else
        writetable(T, filePath);
    end
end

function localAppendLog(logFile, sc, status, message, elapsed_s)
    row = table(sc.scenario_id, string(sc.class_name{1}), string(sc.electrical_fault_family{1}), ...
        string(sc.fault_location_type{1}), sc.fault_distance_m, sc.brightness_index, ...
        string(status), string(message), elapsed_s, ...
        'VariableNames', {'scenario_id','class_name','electrical_fault_family','fault_location_type', ...
                          'fault_distance_m','brightness_index','status','message','elapsed_s'});
    localAppendTable(row, logFile);
end
