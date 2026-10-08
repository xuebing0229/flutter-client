package com.workspace.client.k7m4;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;
import org.junit.Test;
import org.junit.runner.RunWith;

import static org.junit.Assert.*;

/**
 * A synthetic pixel-level test of the actual production buyer-retry path.
 * The original full-screen OCR line list omits the second customer's name,
 * but the drawn image has the name, just like the observed on-device report.
 * The public repository never contains the user's source image or nicknames.
 */
@RunWith(AndroidJUnit4.class)
public final class ScreenshotBuyerRecoveryTest {
    private static final Class<?> LINE;
    private static final Constructor<?> CONSTRUCTOR;
    private static final Method TEXT;
    static {
        try {
            LINE = Class.forName("com.workspace.client.k7m4.ScreenshotOcrBridge$OcrLine");
            CONSTRUCTOR = LINE.getDeclaredConstructor(
                String.class, double.class, double.class, double.class, double.class
            );
            CONSTRUCTOR.setAccessible(true);
            TEXT = LINE.getDeclaredMethod("getText");
            TEXT.setAccessible(true);
        } catch (Exception error) {
            throw new ExceptionInInitializerError(error);
        }
    }

    private static Object box(String text, double x, double y,
                              double right, double bottom) throws Exception {
        return CONSTRUCTOR.newInstance(text, x, y, right, bottom);
    }

    @Test
    public void missingSecondBuyerRecoveredByThreeTimesCrop() throws Exception {
        Bitmap bitmap = Bitmap.createBitmap(865, 1920, Bitmap.Config.ARGB_8888);
        final Canvas canvas = new Canvas(bitmap);
        canvas.drawColor(Color.WHITE);
        final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(Color.BLACK);
        paint.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
        paint.setTextSize(30f);
        canvas.drawText("测试买家乙", 167f, 970f, paint);

        List<Object> firstPass = new ArrayList<>();
        firstPass.add(box("默认", 73, 235, 127, 259));
        firstPass.add(box("购买时间", 636, 231, 785, 261));
        firstPass.add(box("测试买家甲", 167, 383, 275, 408));
        firstPass.add(box("【常驻】测试稿3.0", 347, 496, 694, 531));
        firstPass.add(box("【常驻】测试稿3.0", 362, 1070, 682, 1101));
        firstPass.add(box("测试买家丙", 166, 1531, 280, 1550));
        firstPass.add(box("【常驻】测试稿3.0", 362, 1642, 682, 1674));

        TextRecognizer engine = TextRecognition.getClient(
            new ChineseTextRecognizerOptions.Builder().build());
        try {
            Method retry = ScreenshotOcrBridge.class.getDeclaredMethod(
                "retryMissingMiHuashiBuyers",
                Bitmap.class, TextRecognizer.class, List.class, Function1.class
            );
            retry.setAccessible(true);
            CountDownLatch latch = new CountDownLatch(1);
            AtomicReference<List<?>> result = new AtomicReference<>();
            // The native Task callback uses the main Looper, not the JUnit
            // instrumentation worker thread. Never block the main thread.
            AtomicReference<Throwable> invocationError = new AtomicReference<>();
            InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {
                try {
                    // Activity allocates an Android Handler during construction.
                    // Both its construction and the async ML Kit call belong
                    // on the main Looper, never the instrumentation worker.
                    ScreenshotOcrBridge bridge = new ScreenshotOcrBridge(new Activity());
                    retry.invoke(bridge, bitmap, engine, firstPass,
                        new Function1<List<?>, Unit>() {
                            @Override public Unit invoke(List<?> lines) {
                                result.set(lines);
                                latch.countDown();
                                return Unit.INSTANCE;
                            }
                        }
                    );
                } catch (Throwable error) {
                    invocationError.set(error);
                    latch.countDown();
                }
            });
            assertTrue("Buyer crop timed out", latch.await(70, TimeUnit.SECONDS));
            assertNull("Invocation failed", invocationError.get());
            assertNotNull(result.get());
            assertEquals("The retry must add precisely one missing buyer",
                firstPass.size() + 1, result.get().size());
            boolean recovered = false;
            for (Object line : result.get()) {
                String value = String.valueOf(TEXT.invoke(line));
                if (value.contains("买家乙")) recovered = true;
            }
            assertTrue("The synthetic second buyer should be recovered", recovered);
        } finally {
            engine.close();
            bitmap.recycle();
        }
    }
}
