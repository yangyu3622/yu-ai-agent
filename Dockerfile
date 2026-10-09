# ============ 构建阶段 ============
# 【2026 改动】原版用 maven:3.9-amazoncorretto-21 单阶段构建，镜像体积 900MB+，
# 且每次改一行代码都要重新下载全部依赖。改成多阶段构建：依赖层可缓存，产物仅含 JRE。
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app

# 先只复制 pom，让依赖层可被 Docker 缓存（改代码不触发重新下载）
COPY pom.xml .
RUN mvn -B -q dependency:go-offline -DskipTests || true

COPY src ./src
RUN mvn -B clean package -DskipTests

# ============ 运行阶段 ============
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# PDF 生成工具依赖中文字体（iText STSongStd-Light）
RUN apk add --no-cache tzdata fontconfig \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

COPY --from=build /app/target/yu-ai-agent.jar /app/yu-ai-agent.jar

# 智能体工具（文件读写 / PDF / 下载）的落盘目录
RUN mkdir -p /app/tmp /root/yu-ai-agent/logs

ENV JAVA_OPTS="-Xms256m -Xmx700m -XX:+UseG1GarbageCollector -Dfile.encoding=UTF-8"
ENV SPRING_PROFILES_ACTIVE=prod

EXPOSE 8123

# 用 exec 形式启动，保证能收到 SIGTERM（配合 server.shutdown=graceful 优雅停机）
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/yu-ai-agent.jar"]
