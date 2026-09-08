# Time decoding

## Conventional BCD decoder

The baseline decoder is the normal two-minute strategy:

1. wait for minute start;
2. record one complete minute;
3. verify parity;
4. verify legal minute/hour ranges;
5. record the next minute;
6. verify that the time advanced consistently;
7. retry if any check fails.

This is simple and robust when the raw BER is already low, but it throws away a lot of useful information when individual bits are unreliable.

## Maximum-likelihood decoder used by the demonstration receiver

Engeler's implementation treats the DCF77 stream as a long known temporal code sequence and asks: **which time position is most correlated with everything received so far?**

The receiver stores up to **3600 s** of history. Data are not discarded just because one minute contains parity errors. Once the time is found, future expected bits are almost entirely predictable apart from exceptional events such as leap seconds.

## Hierarchical search instead of a full 24-hour correlation

A mathematically direct decoder could correlate the received history against every second of the known 24-hour sequence. The paper reduces the work by searching hierarchically:

### Step 1: current second / minute start

Correlate against known/constant positions in the frame, particularly the PM minute-start pattern and other known bits. Parity-covered groups can also contribute to the correlation score without first performing conventional BCD decoding.

The maximum correlation gives the most likely current second.

### Step 2: current minute

With second alignment fixed, correlate the minute information using bits **21-28**. Try candidate minute values 0-59 and select the best correlation.

### Step 3: current hour

With minute known, correlate hour bits **29-35** for candidate hours 0-23. The candidate generator must handle a possible hour rollover across the stored observation window.

The paper reports that this partial/hierarchical search is almost as good as a brute-force full correlation: simulated BER performance degradation is less than roughly **0.01 additive BER** for equal decode probability.

## Soft bits

The decoder should ingest a real-valued confidence/evidence sample rather than an immediate hard decision:

```text
-1  => strong evidence for bit 0
 0  => undecided / equal likelihood
+1  => strong evidence for bit 1
```

This matters because noise-crossed samples tend to land near zero. Thresholding them into hard bits loses the information that they were uncertain.

In the paper's simulations, soft bits allow about **0.066 higher raw BER** than hard bits for the same observation time and decode probability. They cost more memory but do not fundamentally change the search algorithm.

## Partial-minute acquisition

The ML decoder starts recording immediately at power-up. It does not need to wait for a minute boundary before collecting useful evidence.

The time can be assembled from frame segments that straddle two minutes. The required information is mainly:

- minute/second alignment from the minute-start pattern;
- minute bits 21-28;
- hour bits 29-35.

With a good signal the paper reports:

- **<= 60 s** to decode regardless of power-up position;
- best case about **35 s** when power-up is aligned favourably;
- longer acquisition under noise, until confidence checks pass.

## Confidence checks

Maximum correlation always produces a winner, even if the input is pure noise. Therefore the implementation must assess the **shape/separation of correlation peaks** and refuse to output a time when confidence is inadequate.

The demonstration receiver is designed for a maximum undetected/wrong decode probability of approximately

```text
p_off <= 5.5e-5
```

The exact numeric thresholds of the confidence test are not published, so this repository must derive them experimentally from simulation and recorded RF data.

A practical confidence metric can include:

- best-vs-second-best second correlation gap;
- best-vs-second-best minute gap;
- best-vs-second-best hour gap;
- parity/range consistency as an additional safety check;
- agreement between AM and PM evidence where both encode the same bit;
- stability of the winning time candidate over successive seconds.

The first three reflect the paper directly; the latter items are conservative implementation additions and should be labelled as such in code.

## Suggested implementation structure

```text
history[3600] = soft bit evidence + validity/quality metadata

once per second:
    append newest soft evidence

    second_scores = correlate history with known frame-position features
    s_hat = argmax(second_scores)

    minute_scores = correlate minute bits for candidates 0..59 at s_hat
    m_hat = argmax(minute_scores)

    hour_scores = correlate hour bits for candidates 0..23,
                  accounting for hour crossing in history
    h_hat = argmax(hour_scores)

    confidence = evaluate_peak_separation(second_scores,
                                          minute_scores,
                                          hour_scores)

    if confidence passes:
        publish time candidate
    else:
        keep accumulating
```

This pseudocode captures the architecture, not the missing implementation constants.

## Performance target

With one hour of history, the paper's ML decoder continues to decode at approximately **BER = 0.34**, whereas a repeatedly retried conventional BCD decoder reaches about **BER = 0.13** over the same maximum 60-minute interval.
