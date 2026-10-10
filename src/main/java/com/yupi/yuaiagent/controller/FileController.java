package com.yupi.yuaiagent.controller;

import com.yupi.yuaiagent.constant.FileConstant;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

@RestController
@RequestMapping("/files")
public class FileController {

    @GetMapping("/download")
    public ResponseEntity<Resource> download(@RequestParam("fileName") String fileName) {
        try {
            // 安全：只取文件名部分，防止 ../../ 目录穿越攻击
            String safeName = Paths.get(fileName).getFileName().toString();
            Path filePath = Paths.get(FileConstant.FILE_SAVE_DIR, "pdf", safeName).normalize();
            if (!Files.exists(filePath)) {
                return ResponseEntity.notFound().build();
            }
            Resource resource = new UrlResource(filePath.toUri());
            String encoded = URLEncoder.encode(safeName, StandardCharsets.UTF_8);
            return ResponseEntity.ok()
                    .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename*=UTF-8''" + encoded)
                    .contentType(MediaType.APPLICATION_PDF)
                    .body(resource);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }
    @GetMapping("/preview")
    public ResponseEntity<Resource> preview(@RequestParam("fileName") String fileName) {
        try {
            String safeName = Paths.get(fileName).getFileName().toString();
            Path filePath = Paths.get(FileConstant.FILE_SAVE_DIR, "pdf", safeName).normalize();
            if (!Files.exists(filePath)) {
                return ResponseEntity.notFound().build();
            }
            Resource resource = new UrlResource(filePath.toUri());
            String encoded = URLEncoder.encode(safeName, StandardCharsets.UTF_8);
            // inline = 浏览器内置预览，而不是直接下载
            return ResponseEntity.ok()
                    .header(HttpHeaders.CONTENT_DISPOSITION, "inline; filename*=UTF-8''" + encoded)
                    .contentType(MediaType.APPLICATION_PDF)
                    .body(resource);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }
}
