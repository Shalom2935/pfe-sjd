function figHandles = DIAM4100_plotValidationResults(varargin)
%DIAM4100_PLOTVALIDATIONRESULTS Plot CCR validation/sweep results.
%
% Usage:
%   DIAM4100_plotValidationResults
%   DIAM4100_plotValidationResults('InputCsv', 'DIAM4100_validation_results.csv')

    opts = localParseInputs(varargin{:});
    thisDir = fileparts(mfilename('fullpath'));
    if isempty(opts.InputCsv)
        opts.InputCsv = fullfile(thisDir, 'DIAM4100_validation_results.csv');
    end
    if isempty(opts.OutputDir)
        opts.OutputDir = fullfile(thisDir, 'figures');
    end
    if ~exist(opts.OutputDir, 'dir')
        mkdir(opts.OutputDir);
    end

    results = readtable(opts.InputCsv);
    results.Brightness = string(results.Brightness);
    brightnessOrder = ["B0","B1","B2","B3","B4","B5"];
    brightnessOrder = brightnessOrder(ismember(brightnessOrder, unique(results.Brightness)));
    loadRatios = unique(results.LoadRatio, 'sorted')';

    passMap = localMetricMap(results, loadRatios, brightnessOrder, "Pass");
    overshootMap = localMetricMap(results, loadRatios, brightnessOrder, "Overshoot_pct");
    finalErrorMap = localMetricMap(results, loadRatios, brightnessOrder, "FinalError_A");
    settlingMap = localMetricMap(results, loadRatios, brightnessOrder, "SettlingTime_s");
    kiMap = localMetricMap(results, loadRatios, brightnessOrder, "Ki");

    figHandles = gobjects(1, 2);

    figHandles(1) = figure('Color', 'white', 'Name', 'DIAM4100 validation heatmaps');
    tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    localHeatmap(loadRatios, brightnessOrder, passMap, 'Validation globale', 'Pass', [0 1]);
    localHeatmap(loadRatios, brightnessOrder, overshootMap, 'Depassement', 'Overshoot (%)', []);
    localHeatmap(loadRatios, brightnessOrder, abs(finalErrorMap), 'Erreur finale absolue', '|erreur| (A)', []);
    localHeatmap(loadRatios, brightnessOrder, settlingMap, 'Temps d''etablissement', 's', []);
    localHeatmap(loadRatios, brightnessOrder, kiMap, 'Ki applique', 'Ki', []);
    nexttile;
    axis off;
    text(0, 0.92, sprintf('Source: %s', opts.InputCsv), 'Interpreter', 'none');
    text(0, 0.72, 'Tap fixe: 4/8. Charge balayee: ratio de la charge LED nominale.');
    text(0, 0.52, 'Pass exige: erreur finale dans la bande, pas de depassement durable, pas de franchissement IEC.');
    text(0, 0.32, 'Les zones rouges/NaN indiquent les points a retuner individuellement.');

    exportgraphics(figHandles(1), fullfile(opts.OutputDir, 'DIAM4100_validation_heatmaps.png'), ...
        'Resolution', opts.Resolution);

    figHandles(2) = figure('Color', 'white', 'Name', 'DIAM4100 validation profiles');
    tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    localProfile(results, 'Overshoot_pct', 'Depassement (%)');
    localProfile(results, 'FinalError_A', 'Erreur finale (A)');
    localProfile(results, 'Ki', 'Ki applique');
    exportgraphics(figHandles(2), fullfile(opts.OutputDir, 'DIAM4100_validation_profiles.png'), ...
        'Resolution', opts.Resolution);

    fprintf('Figures saved in: %s\n', opts.OutputDir);
end

function opts = localParseInputs(varargin)
    parser = inputParser;
    parser.addParameter('InputCsv', '', @(x) ischar(x) || isstring(x));
    parser.addParameter('OutputDir', '', @(x) ischar(x) || isstring(x));
    parser.addParameter('Resolution', 220, @(x) isnumeric(x) && isscalar(x));
    parser.parse(varargin{:});
    opts = parser.Results;
    opts.InputCsv = char(opts.InputCsv);
    opts.OutputDir = char(opts.OutputDir);
end

function metricMap = localMetricMap(results, loadRatios, brightnessOrder, metricName)
    metricMap = nan(numel(brightnessOrder), numel(loadRatios));
    for i = 1:numel(brightnessOrder)
        for j = 1:numel(loadRatios)
            idx = results.LoadRatio == loadRatios(j) & results.Brightness == brightnessOrder(i);
            if any(idx)
                metricMap(i, j) = results.(metricName)(find(idx, 1));
            end
        end
    end
end

function localHeatmap(loadRatios, brightnessOrder, data, titleText, colorbarText, limits)
    nexttile;
    imagesc(loadRatios, 1:numel(brightnessOrder), data);
    set(gca, 'YTick', 1:numel(brightnessOrder), 'YTickLabel', brightnessOrder);
    xlabel('Ratio charge LED nominale');
    ylabel('Brillance');
    title(titleText);
    grid on;
    cb = colorbar;
    if ~isempty(limits)
        caxis(limits);
    end
    ylabel(cb, colorbarText);
end

function localProfile(results, metricName, yLabelText)
    nexttile;
    hold on;
    labels = unique(string(results.Brightness), 'stable');
    for k = 1:numel(labels)
        idx = string(results.Brightness) == labels(k);
        plot(results.LoadRatio(idx), results.(metricName)(idx), '-o', ...
            'DisplayName', labels(k), 'LineWidth', 1.1);
    end
    grid on;
    xlabel('Ratio charge LED nominale');
    ylabel(yLabelText);
    legend('Location', 'bestoutside');
end
