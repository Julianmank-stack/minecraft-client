package dev.metalcraft.engine.safety;

import java.io.IOException;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * Separate renderer log stream (logs/renderer/renderer-<timestamp>.log):
 * backend decisions, capability reports, per-mode timings, fallback events.
 * The launcher's Logs tab has a dedicated Renderer filter reading these files,
 * and crash diagnoses attach them automatically.
 */
public final class RendererLog {

    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("HH:mm:ss.SSS");
    private static Path logFile;

    private RendererLog() {}

    public static synchronized void init(String dirName) {
        try {
            Path dir = Path.of(dirName);
            Files.createDirectories(dir);
            String stamp = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss").format(LocalDateTime.now());
            logFile = dir.resolve("renderer-" + stamp + ".log");
            write("INFO", "MetalCraft Engine renderer log opened");
        } catch (IOException e) {
            System.err.println("[metalcraft] could not open renderer log: " + e.getMessage());
        }
    }

    public static void info(String message) {
        write("INFO", message);
    }

    public static void warn(String message) {
        write("WARN", message);
    }

    public static void error(String message, Throwable t) {
        StringBuilder sb = new StringBuilder(message);
        if (t != null) {
            StringWriter sw = new StringWriter();
            t.printStackTrace(new PrintWriter(sw));
            sb.append('\n').append(sw);
        }
        write("ERROR", sb.toString());
    }

    private static synchronized void write(String level, String message) {
        String line = "[" + TS.format(LocalDateTime.now()) + "] [" + level + "] " + message + "\n";
        System.out.print("[metalcraft] " + line);
        if (logFile != null) {
            try {
                Files.writeString(logFile, line, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            } catch (IOException ignored) {
            }
        }
    }
}
