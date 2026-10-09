package com.yupi.yuaiagent.agent;

import com.yupi.yuaiagent.agent.model.AgentState;
import lombok.Data;
import lombok.EqualsAndHashCode;
import lombok.extern.slf4j.Slf4j;

/**
 * ReAct (Reasoning and Acting) 模式的代理抽象类
 * 实现了思考-行动的循环模式
 */
@EqualsAndHashCode(callSuper = true)
@Data
@Slf4j
public abstract class ReActAgent extends BaseAgent {

    /**
     * 最近一次思考的输出文本。
     * 当 think() 判定"无需再调用工具"时，这段文本就是给用户的最终答复。
     */
    protected String lastThinkText = "";

    public abstract boolean think();

    public abstract String act();

    @Override
    public String step() {
        try {
            boolean shouldAct = think();
            if (!shouldAct) {
                // 无需调用工具即代表任务结束，必须置为 FINISHED，
                // 否则循环会空转到 maxSteps
                setState(AgentState.FINISHED);
                if (lastThinkText != null && !lastThinkText.isEmpty()) {
                    return lastThinkText;
                }
                return "思考完成 - 无需行动";
            }
            return act();
        } catch (Exception e) {
            log.error("步骤执行失败", e);
            return "步骤执行失败：" + e.getMessage();
        }
    }
}