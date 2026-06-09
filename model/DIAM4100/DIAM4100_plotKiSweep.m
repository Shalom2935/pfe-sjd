function figHandles = DIAM4100_plotKiSweep(varargin)
%DIAM4100_PLOTKISWEEP Plot dense Ki sweep and selected schedule.

    opts = localParseInputs(varargin{:});
    thisDir = fileparts(mfilename('fullpath'));
    if isempty(opts.SweepCsv)
        opts.SweepCsv = fullfile(thisDir, 'figures', 'DIAM4100_Ki_sweep_results.csv');
    end
    if isempty(opts.BestCsv)
        opts.BestCsv = fullfile(thisDir, 'figures', 'DIAM4100_Ki_best_schedule.csv');
    end
    if isempty(opts.OutputDir)
        opts.OutputDir = fullfile(thisDir, 'figures');
    end
    if ~exist(opts.OutputDir, 'dir')
        mkdir(opts.OutputDir);
    end

    sweep = readtable(opts.SweepCsv);
    best = readtable(opts.BestCsv);
    sweep.Brightness = string(sweep.Brightness);
    best.Brightness = string(best.Brightness);

    figHandles = gobjects(1, 2);

    labels = unique(sweep.Brightness, 'stable')';
    figHandles(1) = figure('Color', 'white', 'Name', 'DIAM4100 Ki sweep score');
    tiledlayout(2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for label = labels
        nexttile;
        idx = sweep.Brightness == label;
        scatter(sweep.Ki(idx), sweep.LoadRatio(idx), 34, sweep.Score(idx), 'filled');
        hold on;
        bestIdx = best.Brightness == label;
        plot(best.Ki(bestIdx), best.LoadRatio(bestIdx), 'kp-', ...
            'MarkerFaceColor', 'y', 'LineWidth', 1.3);
        grid on;
        xlabel('Ki');
        ylabel('Ratio charge');
        title(sprintf('%s: score tuning', label));
        colorbar;
    end
    exportgraphics(figHandles(1), fullfile(opts.OutputDir, 'DIAM4100_Ki_sweep_score.png'), ...
        'Resolution', opts.Resolution);

    figHandles(2) = figure('Color', 'white', 'Name', 'DIAM4100 selected Ki schedule');
    tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    nexttile;
    hold on;
    for label = labels
        idx = best.Brightness == label;
        plot(best.LoadRatio(idx), best.Ki(idx), '-o', ...
            'DisplayName', label, 'LineWidth', 1.2);
    end
    grid on;
    xlabel('Ratio charge LED nominale');
    ylabel('Ki retenu');
    title('Planning Ki retenu apres sweep');
    legend('Location', 'bestoutside');

    nexttile;
    hold on;
    for label = labels
        idx = best.Brightness == label;
        plot(best.LoadRatio(idx), abs(best.FinalError_A(idx)), '-o', ...
            'DisplayName', label, 'LineWidth', 1.2);
    end
    yline(0.10, '--k', '+/-0.1 A');
    grid on;
    xlabel('Ratio charge LED nominale');
    ylabel('|Erreur finale| (A)');
    title('Erreur finale du planning retenu');
    legend('Location', 'bestoutside');
    exportgraphics(figHandles(2), fullfile(opts.OutputDir, 'DIAM4100_Ki_best_schedule.png'), ...
        'Resolution', opts.Resolution);

    fprintf('Ki sweep figures saved in: %s\n', opts.OutputDir);
end

function opts = localParseInputs(varargin)
    parser = inputParser;
    parser.addParameter('SweepCsv', '', @(x) ischar(x) || isstring(x));
    parser.addParameter('BestCsv', '', @(x) ischar(x) || isstring(x));
    parser.addParameter('OutputDir', '', @(x) ischar(x) || isstring(x));
    parser.addParameter('Resolution', 220, @(x) isnumeric(x) && isscalar(x));
    parser.parse(varargin{:});
    opts = parser.Results;
    opts.SweepCsv = char(opts.SweepCsv);
    opts.BestCsv = char(opts.BestCsv);
    opts.OutputDir = char(opts.OutputDir);
end
