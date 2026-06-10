function scenarios = FaultSim_buildScenarioTable(varargin)
%FAULTSIM_BUILDSCENARIOTABLE Build scenario metadata table for smoke or full runs.
%
% Usage:
%   scenarios = FaultSim_buildScenarioTable('Mode','smoke')
%   scenarios = FaultSim_buildScenarioTable('Mode','full','AcceptUnvalidatedRanges',true)

    parser = inputParser;
    parser.addParameter('Mode', 'full', @(s)ischar(s) || isstring(s));
    parser.addParameter('AcceptUnvalidatedRanges', false, @(x)islogical(x) && isscalar(x));
    parser.parse(varargin{:});

    cfg = FaultSim_config('Mode', parser.Results.Mode, ...
                          'AcceptUnvalidatedRanges', parser.Results.AcceptUnvalidatedRanges);

    geometryFile = fullfile(cfg.paths.metadataDir, 'FaultSim_geometry.mat');
    if ~exist(geometryFile, 'file')
        error('Geometry file not found. Run FaultSim_prepareModel first: %s', geometryFile);
    end
    S = load(geometryFile, 'FullLoop', 'geo');
    FullLoop = S.FullLoop;
    geo = S.geo;

    mode = lower(char(parser.Results.Mode));
    if strcmp(mode, 'full') && ~cfg.acceptUnvalidatedRanges
        error(['Full scenario generation is blocked until you explicitly review the ranges in ', ...
               'FaultSim_config.m. Run with: FaultSim_runBatch(''Mode'',''full'',', ...
               '''AcceptUnvalidatedRanges'',true) after validation.']);
    end

    rows = {};
    id = 0;

    if strcmp(mode, 'smoke')
        brightnessList = cfg.smoke.brightnessList;
        nodeList = unique(round(linspace(1, geo.nodeCount, 5)));
        surgeList = 1:min(2, numel(FullLoop.surge.distance_m));
        moduleList = unique([1, round(numel(FullLoop.loads)/2), numel(FullLoop.loads)]);

        for b = brightnessList
            id = id + 1;
            rows(end+1,:) = localRow(id, 0, 'HEALTHY', 'healthy', false, 'none', NaN, NaN, NaN, NaN, NaN, NaN, '', b); %#ok<AGROW>

            id = id + 1;
            rows(end+1,:) = localRow(id, 1, 'HUMIDITY_PROGRESSIVE', 'insulation_fault', true, ...
                'cable_node', nodeList(2), geo.nodeDistances_m(nodeList(2)), NaN, NaN, cfg.ranges.humidity_R_ohm(3), NaN, '', b); %#ok<AGROW>

            id = id + 1;
            rows(end+1,:) = localRow(id, 2, 'REACTIVE_INCIPIENT', 'insulation_fault', true, ...
                'cable_node', nodeList(3), geo.nodeDistances_m(nodeList(3)), NaN, NaN, NaN, cfg.ranges.reactive_C_F(3), '', b); %#ok<AGROW>

            id = id + 1;
            rows(end+1,:) = localRow(id, 3, 'EARTH_SHORT', 'insulation_fault', true, ...
                'cable_node', nodeList(4), geo.nodeDistances_m(nodeList(4)), NaN, NaN, cfg.ranges.earth_short_R_ohm(3), NaN, '', b); %#ok<AGROW>

            id = id + 1;
            sIdx = surgeList(1);
            sNode = localNearestNode(geo.nodeDistances_m, FullLoop.surge.distance_m(sIdx));
            rows(end+1,:) = localRow(id, 4, 'SURGE_ARRESTER_SHORT', 'insulation_fault', true, ...
                'surge_arrester', sNode, geo.nodeDistances_m(sNode), FullLoop.surge.regardIndex(sIdx), NaN, cfg.ranges.surge_short_R_ohm(2), NaN, '', b); %#ok<AGROW>

            id = id + 1;
            mIdx = moduleList(2);
            mNode = localNearestNode(geo.nodeDistances_m, FullLoop.loads(mIdx).Distance_m);
            rows(end+1,:) = localRow(id, 5, 'TI_INSULATION_LEAKAGE', 'insulation_fault', true, ...
                'TI_primary', mNode, geo.nodeDistances_m(mNode), FullLoop.loads(mIdx).RegardIndex, mIdx, cfg.ranges.ti_leakage_R_ohm(3), NaN, '', b); %#ok<AGROW>

            id = id + 1;
            rows(end+1,:) = localRow(id, 6, 'OPEN_CIRCUIT', 'continuity_fault', false, ...
                'series_node', nodeList(5), geo.nodeDistances_m(nodeList(5)), NaN, NaN, cfg.ranges.open_series_R_ohm(2), NaN, '', b); %#ok<AGROW>

            id = id + 1;
            rows(end+1,:) = localRow(id, 7, 'TI_LOAD_FAULT', 'non_insulation_load_fault', false, ...
                'TI_secondary_load', NaN, FullLoop.loads(moduleList(1)).Distance_m, FullLoop.loads(moduleList(1)).RegardIndex, moduleList(1), NaN, NaN, 'open', b); %#ok<AGROW>
        end
    else
        brightnessList = cfg.full.brightnessList;
        nodeList = 1:cfg.full.locationStride:geo.nodeCount;

        for b = brightnessList
            id = id + 1;
            rows(end+1,:) = localRow(id, 0, 'HEALTHY', 'healthy', false, 'none', NaN, NaN, NaN, NaN, NaN, NaN, '', b); %#ok<AGROW>

            for node = nodeList
                for r = cfg.ranges.humidity_R_ohm
                    id = id + 1;
                    rows(end+1,:) = localRow(id, 1, 'HUMIDITY_PROGRESSIVE', 'insulation_fault', true, 'cable_node', node, geo.nodeDistances_m(node), NaN, NaN, r, NaN, '', b); %#ok<AGROW>
                end
                for c = cfg.ranges.reactive_C_F
                    id = id + 1;
                    rows(end+1,:) = localRow(id, 2, 'REACTIVE_INCIPIENT', 'insulation_fault', true, 'cable_node', node, geo.nodeDistances_m(node), NaN, NaN, NaN, c, '', b); %#ok<AGROW>
                end
                for r = cfg.ranges.earth_short_R_ohm
                    id = id + 1;
                    rows(end+1,:) = localRow(id, 3, 'EARTH_SHORT', 'insulation_fault', true, 'cable_node', node, geo.nodeDistances_m(node), NaN, NaN, r, NaN, '', b); %#ok<AGROW>
                end
                for r = cfg.ranges.open_series_R_ohm
                    id = id + 1;
                    rows(end+1,:) = localRow(id, 6, 'OPEN_CIRCUIT', 'continuity_fault', false, 'series_node', node, geo.nodeDistances_m(node), NaN, NaN, r, NaN, '', b); %#ok<AGROW>
                end
            end

            for sIdx = 1:numel(FullLoop.surge.distance_m)
                sNode = localNearestNode(geo.nodeDistances_m, FullLoop.surge.distance_m(sIdx));
                for r = cfg.ranges.surge_short_R_ohm
                    id = id + 1;
                    rows(end+1,:) = localRow(id, 4, 'SURGE_ARRESTER_SHORT', 'insulation_fault', true, 'surge_arrester', sNode, geo.nodeDistances_m(sNode), FullLoop.surge.regardIndex(sIdx), NaN, r, NaN, '', b); %#ok<AGROW>
                end
            end

            for mIdx = 1:numel(FullLoop.loads)
                mNode = localNearestNode(geo.nodeDistances_m, FullLoop.loads(mIdx).Distance_m);
                for r = cfg.ranges.ti_leakage_R_ohm
                    id = id + 1;
                    rows(end+1,:) = localRow(id, 5, 'TI_INSULATION_LEAKAGE', 'insulation_fault', true, 'TI_primary', mNode, geo.nodeDistances_m(mNode), FullLoop.loads(mIdx).RegardIndex, mIdx, r, NaN, '', b); %#ok<AGROW>
                end
                for modeName = cfg.ranges.loadFaultModes
                    id = id + 1;
                    rows(end+1,:) = localRow(id, 7, 'TI_LOAD_FAULT', 'non_insulation_load_fault', false, 'TI_secondary_load', NaN, FullLoop.loads(mIdx).Distance_m, FullLoop.loads(mIdx).RegardIndex, mIdx, NaN, NaN, modeName{1}, b); %#ok<AGROW>
                end
            end
        end
    end

    scenarios = cell2table(rows, 'VariableNames', localColumns());
    scenarios.brightness_label = arrayfun(@(b)sprintf('B%d', b-1), scenarios.brightness_index, 'UniformOutput', false);
    scenarios.is_location_valid = ~strcmp(scenarios.class_name, 'HEALTHY');

    if ~exist(cfg.paths.metadataDir, 'dir')
        mkdir(cfg.paths.metadataDir);
    end
    outFile = fullfile(cfg.paths.metadataDir, sprintf('FaultSim_scenarios_%s.csv', mode));
    writetable(scenarios, outFile);
    fprintf('[OK] Scenario table written: %s (%d scenarios)\n', outFile, height(scenarios));
end

function cols = localColumns()
    cols = {'scenario_id','class_id','class_name','fault_group','is_insulation_fault', ...
            'fault_location_type','node_index','fault_distance_m','fault_regard_index', ...
            'fault_module_index','fault_R_ohm','fault_C_F','load_fault_mode','brightness_index'};
end

function row = localRow(id, classId, className, group, isIso, locType, nodeIdx, dist, regardIdx, moduleIdx, R, C, loadMode, brightnessIdx)
    row = {id, classId, className, group, isIso, locType, nodeIdx, dist, regardIdx, moduleIdx, R, C, loadMode, brightnessIdx};
end

function idx = localNearestNode(nodeDistances_m, distance_m)
    [~, idx] = min(abs(nodeDistances_m - distance_m));
end
