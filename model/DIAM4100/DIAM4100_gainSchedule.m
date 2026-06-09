function Ki = DIAM4100_gainSchedule(Iref_Arms, loadPower_VA, schedule)
%DIAM4100_GAINSCHEDULE Initial integral-gain scheduling for the DIAM4100 CCR.
%
% Ki is indexed by brightness current and by the effective load connected
% to the CCR secondary. The load tapping is intentionally not an axis of
% this schedule for the Douala loop study: it is fixed at 4/8 by design.
%
% After running DIAM4100_validateControl, replace the default table by a
% tuned table if a stricter operating envelope is needed.

    if nargin < 3 || isempty(schedule)
        schedule = DIAM4100_defaultSchedule();
    end

    Iref_Arms = max(min(Iref_Arms, max(schedule.currentGrid_Arms)), ...
                    min(schedule.currentGrid_Arms));
    loadPower_VA = max(min(loadPower_VA, max(schedule.loadPowerGrid_VA)), ...
                       min(schedule.loadPowerGrid_VA));

    Ki = interp2(schedule.loadPowerGrid_VA, ...
                 schedule.currentGrid_Arms, ...
                 schedule.KiTable, ...
                 loadPower_VA, ...
                 Iref_Arms, ...
                 'linear');
end

function schedule = DIAM4100_defaultSchedule()
    currentGrid_Arms = [1.50 2.80 3.40 4.10 5.20 6.60];
    nominalLoad_VA = 2442;
    loadPowerGrid_VA = nominalLoad_VA * [0.20 0.35 0.50 0.75 1.00 1.20];

    Ki_ref = 200;
    I_ref = 6.6;
    load_ref_VA = nominalLoad_VA;
    Ki_min = 60;
    Ki_max = 300;

    KiTable = zeros(numel(currentGrid_Arms), numel(loadPowerGrid_VA));
    for i = 1:numel(currentGrid_Arms)
        for j = 1:numel(loadPowerGrid_VA)
            currentFactor = (I_ref / currentGrid_Arms(i))^0.10;
            loadFactor = (loadPowerGrid_VA(j) / load_ref_VA)^0.65;
            KiTable(i, j) = min(max(Ki_ref * currentFactor * loadFactor, Ki_min), Ki_max);
        end
    end

    schedule = struct();
    schedule.currentGrid_Arms = currentGrid_Arms;
    schedule.loadPowerGrid_VA = loadPowerGrid_VA;
    schedule.KiTable = KiTable;
end
