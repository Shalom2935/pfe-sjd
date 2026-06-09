function metrics = DIAM4100_measureResponse(t_s, y_Arms, ref_Arms, norms)
%DIAM4100_MEASURERESPONSE Compute CCR current-response validation metrics.

    t_s = t_s(:);
    y_Arms = y_Arms(:);

    finiteIdx = isfinite(t_s) & isfinite(y_Arms);
    t_s = t_s(finiteIdx);
    y_Arms = y_Arms(finiteIdx);

    metrics = struct();
    metrics.reference_Arms = ref_Arms;
    metrics.peak_Arms = max(y_Arms);
    metrics.final_Arms = y_Arms(end);
    metrics.finalError_A = metrics.final_Arms - ref_Arms;
    metrics.overshoot_A = max(0, metrics.peak_Arms - ref_Arms);
    metrics.overshoot_pct = 100 * metrics.overshoot_A / max(ref_Arms, eps);

    tolerance_A = norms.FAA.currentTolerance_A;
    inBand = abs(y_Arms - ref_Arms) <= tolerance_A;
    metrics.settlingTime_s = NaN;
    for k = 1:numel(inBand)
        if all(inBand(k:end))
            metrics.settlingTime_s = t_s(k) - t_s(1);
            break;
        end
    end

    transientLimit = norms.FAA.maxTransientRatio * ref_Arms;
    metrics.maxContinuous120Duration_s = localMaxContinuousDuration(t_s, y_Arms > transientLimit);
    metrics.exceedsIECStepLimit = metrics.peak_Arms > norms.IEC.maxStepOvershoot_Arms;
    metrics.exceedsFAA120Duration = metrics.maxContinuous120Duration_s > ...
                                    norms.FAA.maxTransientDuration_s;
    metrics.meetsFAASettling = ~isnan(metrics.settlingTime_s) && ...
                               metrics.settlingTime_s <= norms.FAA.controlSettlingTime_s && ...
                               abs(metrics.finalError_A) <= tolerance_A;
    metrics.meetsIECSettling = ~isnan(metrics.settlingTime_s) && ...
                               metrics.settlingTime_s <= norms.IEC.settlingTime_s && ...
                               abs(metrics.finalError_A) <= tolerance_A;
    metrics.pass = metrics.meetsFAASettling && ...
                   ~metrics.exceedsFAA120Duration && ...
                   ~metrics.exceedsIECStepLimit;
end

function duration_s = localMaxContinuousDuration(t_s, mask)
    duration_s = 0;
    if numel(t_s) < 2 || ~any(mask)
        return;
    end

    dt = [diff(t_s); median(diff(t_s))];
    currentDuration = 0;
    for k = 1:numel(mask)
        if mask(k)
            currentDuration = currentDuration + dt(k);
            duration_s = max(duration_s, currentDuration);
        else
            currentDuration = 0;
        end
    end
end
