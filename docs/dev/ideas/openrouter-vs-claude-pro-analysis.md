# OpenRouter vs Claude Pro ($20/mo): Token Value Analysis

**Date:** 2026-04-22
**Use case:** ~85% coding (agentic, Claude Code style), ~15% research for new feature development
**Methodology:** OpenRouter prices fetched directly from model pages. Claude Pro budget estimated from field reports (Anthropic does not publish). Quality multipliers derived from public benchmarks + community field reports.

---

## 1. OpenRouter Pricing (per million tokens)

Prices fetched from OpenRouter model pages on 2026-04-22.

| Model             | Input $/M | Output $/M | Context | Notes                               |
| ----------------- | --------- | ---------- | ------- | ----------------------------------- |
| Qwen 3.6 Plus     | $0.325    | $1.95      | 1M      | Free preview currently available    |
| Kimi K2.5         | $0.44     | $2.00      | 262K    |                                     |
| Kimi K2.6         | $0.80     | $3.50      | 262K    | Released 2026-04-20, open-weight    |
| GLM-5.1           | $1.05     | $3.50      | 203K    | Trained on Huawei Ascend, no Nvidia |
| Claude Sonnet 4.6 | $3.00     | $15.00     | 1M      |                                     |
| Claude Opus 4.6   | $15.00    | $75.00     | 200K    |                                     |

## 2. Estimating Claude Pro Token Budget

Anthropic does not publish token limits. Sources used:

- Anthropic's own reported average: ~$6/day API-equivalent per developer (90% under $12/day)
- Community-measured 5-hour window: ~44K tokens for Pro (likely undercounts cache reads)
- Weekly hard cap exists (introduced Aug 2025), unpublished
- Usage shared across claude.ai, Claude Code, and Claude Desktop
- Some users report being capped to ~12 usable days/month during peak demand

**Estimated monthly API-equivalent value of Pro subscription:**

| Scenario                   | Working days | API equiv | Tokens (Sonnet blend) |
| -------------------------- | ------------ | --------- | --------------------- |
| Constrained (peak-limited) | ~12          | ~$72      | ~13M                  |
| Typical developer          | ~22          | ~$132     | ~24M                  |
| Light user                 | ~15          | ~$90      | ~17M                  |

Calculation: $6/day at Sonnet 4.6 blended rate of $5.40/M tokens (assuming 4:1 input:output ratio).

The Pro subscription represents roughly a **6.5x discount** over API pricing ($20 buys ~$132 of API tokens).

## 3. Raw Token Comparison

**Assumptions:** 4:1 input:output token ratio (typical for coding — large context, shorter responses). Blended cost = 0.8 x input + 0.2 x output.

| Model                         | Blended $/M          | Tokens for $20 | vs Pro typical (24M) |
| ----------------------------- | -------------------- | -------------- | -------------------- |
| Qwen 3.6 Plus                 | $0.65                | 30.8M          | 1.28x more           |
| Kimi K2.5                     | $0.75                | 26.6M          | 1.11x more           |
| Kimi K2.6                     | $1.34                | 14.9M          | 0.62x (less)         |
| GLM-5.1                       | $1.54                | 13.0M          | 0.54x (less)         |
| Claude Sonnet 4.6 (API)       | $5.40                | 3.7M           | 0.15x (much less)    |
| Claude Opus 4.6 (API)         | $27.00               | 0.74M          | 0.03x (tiny)         |
| **Claude Pro (subscription)** | **~$0.83 effective** | **~24M**       | **baseline**         |

## 4. Quality Multipliers

Raw tokens are meaningless without accounting for how many tokens each model needs to achieve the same outcome. A weaker model that needs 2 retries to get it right costs 3x the tokens for the same result.

### Benchmark Summary (coding-relevant)

| Benchmark           | Opus 4.6 | Sonnet 4.6 | Qwen 3.6+ | GLM-5.1 | Kimi K2.5 | Kimi K2.6 |
| ------------------- | -------- | ---------- | --------- | ------- | --------- | --------- |
| SWE-bench Verified  | 80.8%    | 79.6%      | 78.8%     | 77.8%   | 76.8%     | —         |
| SWE-bench Pro       | 53.4%    | —          | —         | 58.4%   | —         | 58.6%     |
| BenchLM Coding Avg  | —        | 66.4       | —         | 58.4    | —         | 72        |
| BenchLM Agentic Avg | —        | 65.3       | —         | 65.3    | 54.6      | 73.1      |
| BenchLM Total       | —        | 86         | 77        | 79      | 68        | 83        |

### Estimated Quality Multiplier (tokens needed vs Sonnet 4.6 for same outcome)

These are estimates with HIGH uncertainty. They account for: benchmark gaps, instruction-following reliability, retry rates, ecosystem maturity, and field reports. A multiplier of 1.3x means you need 30% more tokens to get the same job done.

| Model             | Multiplier | Rationale                                                                                                                                                                                                                                                      |
| ----------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Qwen 3.6 Plus** | 1.2x       | Close on SWE-bench Verified (78.8 vs 79.6). Aggregate gap wider (77 vs 86 BenchLM). Slightly worse instruction following in complex multi-step coding. Strong on speed (~3x Opus inference).                                                                   |
| **GLM-5.1**       | 1.3x       | Strong on SWE-bench Pro (58.4, beats Opus's 53.4). But BenchLM coding avg 58.4 vs Sonnet's 66.4 — 12% gap. Knowledge score much weaker (52.3 vs 73.7) — matters for research tasks. 8-hour autonomous execution is unique.                                     |
| **Kimi K2.5**     | 1.35x      | SWE-bench Verified 76.8 vs Sonnet's 79.6. BenchLM total 68 vs 86. Weakest agentic score (54.6). Solid baseline but outclassed by its successor and peers.                                                                                                      |
| **Kimi K2.6**     | 1.2x       | Leads SWE-bench Pro (58.6). BenchLM coding avg 72 (best in table). But released 2 days ago — benchmarks self-reported, real-world reports sparse. Agent swarm architecture promising but untested at scale. Discounted from ~1.1x to 1.2x for immaturity risk. |

## 5. Quality-Adjusted Token Comparison

The key table. "Effective tokens" = raw tokens / quality multiplier. This estimates how many Sonnet-4.6-equivalent successful output tokens you get for $20.

| Model                   | Raw tokens ($20) | Quality mult. | **Effective tokens** | **vs Pro (24M)** |
| ----------------------- | ---------------- | ------------- | -------------------- | ---------------- |
| **Qwen 3.6 Plus**       | 30.8M            | 1.2x          | **25.7M**            | **1.07x**        |
| **Kimi K2.5**           | 26.6M            | 1.35x         | **19.7M**            | **0.82x**        |
| **Kimi K2.6**           | 14.9M            | 1.2x          | **12.4M**            | **0.52x**        |
| **GLM-5.1**             | 13.0M            | 1.3x          | **10.0M**            | **0.42x**        |
| Claude Sonnet 4.6 (API) | 3.7M             | 1.0x          | 3.7M                 | 0.15x            |
| Claude Opus 4.6 (API)   | 0.74M            | ~0.85x        | 0.87M                | 0.04x            |
| **Claude Pro**          | ~24M             | 1.0x          | **~24M**             | **baseline**     |

## 6. Verdict

**Your hypothesis — that OpenRouter Chinese models beat Claude Pro on value — is weak after quality adjustment.**

- **Qwen 3.6 Plus** is the only model that's roughly equivalent (~1.07x Pro). And it's currently free in preview, making it worth testing at zero cost.
- **Kimi K2.5** falls below Pro after quality adjustment (0.82x).
- **GLM-5.1 and Kimi K2.6** are significantly worse value than Pro despite cheaper token prices. The Pro subscription discount (~6.5x vs API) is too large to overcome.
- **Claude via OpenRouter API** is terrible value compared to Pro — you're paying full API price without the subscription discount.

### The real calculus

Claude Pro's value comes from the subscription discount, not token pricing. You're getting ~$132/mo of API tokens for $20. The Chinese models would need to be ~6.5x cheaper than Claude API *and* equal quality to match — Qwen 3.6 Plus comes closest (8.3x cheaper blended, ~1.2x quality penalty).

### When OpenRouter does make sense

- **Supplementary use**: Pro for primary coding, cheap OpenRouter models for bulk/parallel tasks (test generation, boilerplate, translation)
- **Specific strengths**: GLM-5.1 for 8-hour autonomous runs, Kimi K2.6 for agent swarms — if your workflow benefits from these unique capabilities
- **Exceeding Pro limits**: If you hit Pro weekly caps regularly, OpenRouter as overflow at ~$0.65-1.54/M is far cheaper than upgrading to Max ($100/mo)

## 7. Caveats and Unknowns

- Quality multipliers are rough estimates from benchmarks + field reports. Your specific codebase/workflow could diverge significantly.
- Claude Pro token budget is estimated, not measured. Your actual budget depends on model mix (any Opus use drains it ~5x faster), peak-hour usage, and weekly cap enforcement.
- Kimi K2.6 is 2 days old. Benchmarks are self-reported. Real-world performance may differ.
- Chinese model ecosystem tooling (IDE integration, MCP support, tool use reliability) is less mature than Claude's.
- The 15% research component of your work favors Claude — knowledge benchmarks show larger gaps than coding benchmarks.
- OpenRouter adds no markup on most models but routing/provider choice can affect latency and reliability.

---

## 8. Research & Planning: Opus 4.6 as Baseline

The above analysis uses Sonnet 4.6 as baseline — appropriate for coding. But for **research and planning for feature development**, Opus 4.6 is the relevant baseline. This changes the analysis dramatically.

### Why it changes

1. **Pro's Opus budget is ~5x smaller.** Opus costs ~5x more per token than Sonnet. If Pro gives ~24M Sonnet tokens, you get ~4.8M Opus tokens.
2. **Knowledge gaps are wider than coding gaps.** Chinese models trail Opus more on GPQA/HLE/knowledge than on SWE-bench.
3. **Two additional Chinese models matter for research**: DeepSeek R1 (reasoning specialist) and DeepSeek V3.2 (absurdly cheap bulk work).

### Additional models for research

| Model         | Input $/M | Output $/M | Context | Notes                                |
| ------------- | --------- | ---------- | ------- | ------------------------------------ |
| DeepSeek V3.2 | $0.252    | $0.378     | 131K    | Cheapest capable model on OpenRouter |
| DeepSeek R1   | $0.70     | $2.50      | 164K    | Premier Chinese reasoning model      |

DeepSeek V4 is NOT yet available on OpenRouter (as of 2026-04-22, despite some premature third-party guides).

### Research-relevant benchmarks

| Benchmark         | Opus 4.6 | Kimi K2.6 | GLM-5.1 | Qwen 3.6+ | DeepSeek R1 | DeepSeek V3.2 |
| ----------------- | -------- | --------- | ------- | --------- | ----------- | ------------- |
| GPQA Diamond      | 91.3%    | 90.5%     | < Opus  | —         | —           | —             |
| HLE (w/ tools)    | 53.0%    | 54.0%     | < Opus  | —         | —           | —             |
| BenchLM Knowledge | ~73.7*   | —         | 52.3    | —         | —           | —             |
| BenchLM Total     | ~90+*    | 83        | 79      | 77        | —           | 65            |

*Opus scores estimated from Sonnet (86) + typical Opus premium. Exact BenchLM Opus scores not published in sources reviewed.

### Raw tokens for $20 (research ratio)

For research, output is proportionally larger (summaries, analysis, plans). Using **3:1 input:output ratio** instead of 4:1. Blended = 0.75 x input + 0.25 x output.

| Model                      | Blended $/M     | Tokens for $20 |
| -------------------------- | --------------- | -------------- |
| DeepSeek V3.2              | $0.28           | 70.4M          |
| Qwen 3.6 Plus              | $0.73           | 27.4M          |
| Kimi K2.5                  | $0.83           | 24.1M          |
| DeepSeek R1                | $1.15           | 17.4M          |
| Kimi K2.6                  | $1.48           | 13.6M          |
| GLM-5.1                    | $1.66           | 12.0M          |
| Claude Sonnet 4.6 (API)    | $6.00           | 3.3M           |
| Claude Opus 4.6 (API)      | $30.00          | 0.67M          |
| **Claude Pro (Opus mode)** | **~$4.17 eff.** | **~4.8M**      |

Claude Pro Opus budget: ~24M Sonnet tokens / 5 (Opus cost multiplier) = ~4.8M tokens.

### Quality multipliers vs Opus 4.6 (research tasks)

Research quality depends on: knowledge breadth, reasoning depth, factual accuracy, instruction following for complex analysis. Gaps are larger here than in coding.

| Model             | Multiplier vs Opus | Rationale                                                                                                                                                                                                 |
| ----------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **DeepSeek R1**   | 1.5x               | Purpose-built reasoner. Strong on math/logic. Weaker on broad knowledge and nuanced planning vs Opus. No published GPQA/HLE scores found, but R1-class models are the strongest Chinese reasoning option. |
| **Kimi K2.6**     | 1.3x               | HLE 54.0% slightly beats Opus's 53.0%. GPQA 90.5% close to 91.3%. Best Chinese model for research. But 2 days old, self-reported benchmarks.                                                              |
| **Qwen 3.6 Plus** | 1.6x               | BenchLM total 77 vs Opus ~90+. No published GPQA/HLE scores. Weaker instruction following on complex multi-step analysis. Strong context window (1M) helps for long documents.                            |
| **GLM-5.1**       | 1.8x               | Knowledge score 52.3 vs Sonnet's 73.7 — large gap. Strong on math reasoning (AIME 92.7%) but weak on broad knowledge. Research is knowledge-heavy.                                                        |
| **Kimi K2.5**     | 1.9x               | BenchLM total 68. Outclassed by K2.6 on every research-relevant metric.                                                                                                                                   |
| **DeepSeek V3.2** | 2.2x               | BenchLM total 65. Cheapest model but significantly weaker on reasoning/knowledge. Good for bulk summarisation, poor for deep analysis.                                                                    |

### Quality-adjusted research tokens: the key table

"Effective tokens" = raw tokens / quality multiplier. Estimates Opus-equivalent research output for $20.

| Model                 | Raw tokens ($20) | Quality mult. | **Effective tokens** | **vs Pro Opus (4.8M)** |
| --------------------- | ---------------- | ------------- | -------------------- | ---------------------- |
| **DeepSeek V3.2**     | 70.4M            | 2.2x          | **32.0M**            | **6.7x more**          |
| **Qwen 3.6 Plus**     | 27.4M            | 1.6x          | **17.1M**            | **3.6x more**          |
| **Kimi K2.5**         | 24.1M            | 1.9x          | **12.7M**            | **2.6x more**          |
| **DeepSeek R1**       | 17.4M            | 1.5x          | **11.6M**            | **2.4x more**          |
| **Kimi K2.6**         | 13.6M            | 1.3x          | **10.5M**            | **2.2x more**          |
| **GLM-5.1**           | 12.0M            | 1.8x          | **6.7M**             | **1.4x more**          |
| Claude Opus 4.6 (API) | 0.67M            | 1.0x          | 0.67M                | 0.14x                  |
| **Claude Pro (Opus)** | ~4.8M            | 1.0x          | **~4.8M**            | **baseline**           |

### Research verdict: hypothesis holds

**Every model beats Claude Pro when you're using Opus for research.** The subscription discount that makes Pro unbeatable for Sonnet-based coding collapses when you switch to Opus, because Pro's Opus budget is tiny (~4.8M tokens/month).

Best research value tiers:
1. **DeepSeek V3.2** — absurd volume (6.7x Pro), but quality penalty is real. Best for: bulk summarisation, initial literature sweeps, extracting info from large documents.
2. **Qwen 3.6 Plus / DeepSeek R1** — sweet spot. 2.4-3.6x Pro. R1 for deep reasoning, Qwen for breadth + 1M context.
3. **Kimi K2.6** — closest to Opus quality (1.3x multiplier), still 2.2x more effective tokens. Best single-model replacement if you want minimal quality loss.

### Recommended strategy

**Hybrid approach for your 85/15 split:**
- **Coding (85%)**: Claude Pro with Sonnet 4.6. Pro wins on value here. No change from Section 6.
- **Research (15%)**: Supplement with OpenRouter. $3-5/month on DeepSeek R1 or Kimi K2.6 gets you more research tokens than Pro's entire Opus budget.
- **Overflow**: When you hit Pro weekly caps, OpenRouter Chinese models for coding at $0.65-1.54/M blended.

Total cost: ~$23-25/mo for meaningfully more capacity than Pro alone, especially on research.

### Caveats specific to research use

- Quality multipliers for research are harder to estimate than coding — no equivalent of SWE-bench pass/fail. These are rougher than Section 4.
- Opus excels at nuanced, multi-constraint reasoning (e.g., "evaluate this architecture against these 5 criteria"). Chinese models may need more explicit prompting to match.
- DeepSeek models have known censorship on politically sensitive topics. Unlikely to matter for feature development research, but worth noting.
- DeepSeek V4 (not yet available) will likely be the strongest Chinese research model when it launches. Watch for it.

---

## Sources

### Pricing
- [OpenRouter: GLM-5.1](https://openrouter.ai/z-ai/glm-5.1)
- [OpenRouter: Qwen 3.6 Plus](https://openrouter.ai/qwen/qwen3.6-plus)
- [OpenRouter: Kimi K2.5](https://openrouter.ai/moonshotai/kimi-k2.5)
- [OpenRouter: Kimi K2.6](https://openrouter.ai/moonshotai/kimi-k2.6)
- [OpenRouter: Claude Opus 4](https://openrouter.ai/anthropic/claude-opus-4)
- [OpenRouter: Claude Sonnet 4](https://openrouter.ai/anthropic/claude-sonnet-4)

### Claude Pro Usage Estimates
- [Faros: Claude Code Token Limits](https://www.faros.ai/blog/claude-code-token-limits)
- [Verdent: Claude Code Pricing 2026](https://www.verdent.ai/guides/claude-code-pricing-2026)
- [DevOps.com: Token Drain Crisis](https://devops.com/claude-code-quota-limits-usage-problems/)
- [The Register: Claude Code Quotas](https://www.theregister.com/2026/03/31/anthropic_claude_code_limits/)
- [ccusage (GitHub)](https://github.com/ryoppippi/ccusage)

### Benchmarks
- [BenchLM: Sonnet 4.6 vs GLM-5.1](https://benchlm.ai/compare/claude-sonnet-4-6-vs-glm-5-1)
- [BenchLM: Sonnet 4.6 vs Qwen 3.6 Plus](https://benchlm.ai/compare/claude-sonnet-4-6-vs-qwen3-6-plus)
- [BenchLM: Kimi 2.6 vs Kimi K2.5](https://benchlm.ai/compare/kimi-2-6-vs-kimi-k2-5)
- [Apiyi: GLM-5.1 vs Sonnet 4.6 Coding](https://help.apiyi.com/en/glm-5-1-vs-claude-sonnet-4-6-coding-comparison-en.html)
- [BuildFastWithAI: Kimi K2.6 vs GPT vs Claude](https://www.buildfastwithai.com/blogs/kimi-k2-6-vs-gpt-claude-benchmarks)
- [MindStudio: Qwen 3.6 Plus vs Opus 4.6](https://www.mindstudio.ai/blog/qwen-3-6-plus-vs-claude-opus-4-6-agentic-coding)
- [Vals.ai: SWE-bench](https://www.vals.ai/benchmarks/swebench)

### Research & Knowledge Benchmarks
- [BenchLM: Knowledge Benchmarks 2026](https://benchlm.ai/knowledge)
- [GPQA Leaderboard 2026](https://pricepertoken.com/leaderboards/benchmark/gpqa)
- [Vellum: LLM Leaderboard 2026](https://www.vellum.ai/llm-leaderboard)
- [BuildFastWithAI: Best AI Models April 2026](https://www.buildfastwithai.com/blogs/best-ai-models-april-2026)
- [BenchLM: Best Chinese LLMs 2026](https://benchlm.ai/blog/posts/best-chinese-llm)
- [WaveSpeedAI: GLM-5.1 vs Claude/GPT/Gemini/DeepSeek](https://wavespeed.ai/blog/posts/glm-5-1-vs-claude-gpt-gemini-deepseek-llm-comparison/)

### DeepSeek Pricing
- [OpenRouter: DeepSeek V3.2](https://openrouter.ai/deepseek/deepseek-v3.2)
- [OpenRouter: DeepSeek R1](https://openrouter.ai/deepseek/deepseek-r1)
- [NxCode: DeepSeek API Pricing 2026](https://www.nxcode.io/resources/news/deepseek-api-pricing-complete-guide-2026)


--- 

## Personal Conclusion

- opencode Go seems to be the simplest solution to get chinese models from good providers with ZDR, but per token costs are 20-50% higher than same model on openrouter
- Opus equivalent probably Kimi K2.6
- Sonnet equivalent probably Qwen 3.6Plus
- For sonnet, analysis shows Qwen is borderline equivalent to the Claude Pro subscription at openrouter prices, but at opencode Go prices, probably Claude Pro is better
- For opus, Kimi 2.6 is equivalent. 2x the value than claude subscription. 