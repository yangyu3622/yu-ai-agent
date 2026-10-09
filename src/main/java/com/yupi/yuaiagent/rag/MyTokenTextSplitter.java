package com.yupi.yuaiagent.rag;

import org.springframework.ai.document.Document;
import org.springframework.ai.transformer.splitter.TokenTextSplitter;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * 自定义基于 Token 的切词器
 */
@Component
public class MyTokenTextSplitter {

    public List<Document> splitDocuments(List<Document> documents) {
        TokenTextSplitter splitter = TokenTextSplitter.builder().build();
        return splitter.apply(documents);
    }

    /**
     * 自定义切分参数
     *
     * @apiNote 【2026 改动】Spring AI 1.1.x 起 TokenTextSplitter 只保留无参构造器和
     * 6 参构造器（多一个 punctuationMarks），原来的
     * new TokenTextSplitter(200, 100, 10, 5000, true) 已无法编译，改用 builder。
     */
    public List<Document> splitCustomized(List<Document> documents) {
        TokenTextSplitter splitter = TokenTextSplitter.builder()
                .withChunkSize(200)
                .withMinChunkSizeChars(100)
                .withMinChunkLengthToEmbed(10)
                .withMaxNumChunks(5000)
                .withKeepSeparator(true)
                .build();
        return splitter.apply(documents);
    }
}
