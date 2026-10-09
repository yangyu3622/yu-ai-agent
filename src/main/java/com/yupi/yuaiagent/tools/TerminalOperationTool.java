package com.yupi.yuaiagent.tools;

import lombok.extern.slf4j.Slf4j;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

/**
 * 终端操作工具
 *
 * @apiNote 【2026 改动】原版硬编码 cmd.exe，部署到 Linux 服务器（阿里云轻量）后直接报
 * IOException: Cannot run program "cmd.exe"。改成按 OS 自动选择 shell，并补上超时控制，
 * 避免 AI 调用死循环命令把服务器卡死。
 */
@Slf4j
public class TerminalOperationTool {

    /** 单条命令最大执行时间（秒） */
    private static final long TIMEOUT_SECONDS = 60;

    @Tool(description = "Execute a command in the terminal")
    public String executeTerminalCommand(@ToolParam(description = "Command to execute in the terminal") String command) {
        StringBuilder output = new StringBuilder();
        try {
            boolean isWindows = System.getProperty("os.name").toLowerCase().contains("win");
            ProcessBuilder builder = isWindows
                    ? new ProcessBuilder("cmd.exe", "/c", command)
                    : new ProcessBuilder("/bin/sh", "-c", command);
            builder.redirectErrorStream(true);
            Process process = builder.start();
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    output.append(line).append("\n");
                }
            }
            // 必须设置超时，否则 AI 触发 tail -f、yes 之类的命令会永久阻塞
            if (!process.waitFor(TIMEOUT_SECONDS, TimeUnit.SECONDS)) {
                process.destroyForcibly();
                output.append("\n[命令执行超时，已强制终止（>").append(TIMEOUT_SECONDS).append("s）]");
                return output.toString();
            }
            int exitCode = process.exitValue();
            if (exitCode != 0) {
                output.append("Command execution failed with exit code: ").append(exitCode);
            }
        } catch (IOException | InterruptedException e) {
            if (e instanceof InterruptedException) {
                Thread.currentThread().interrupt();
            }
            output.append("Error executing command: ").append(e.getMessage());
        }
        return output.toString();
    }
}
