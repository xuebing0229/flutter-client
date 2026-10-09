package com.workspace.client.k7m4;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.util.Log;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import com.equationl.ncnnandroidppocr.OCR;
import com.equationl.ncnnandroidppocr.bean.Device;
import com.equationl.ncnnandroidppocr.bean.DrawModel;
import com.equationl.ncnnandroidppocr.bean.ImageSize;
import com.equationl.ncnnandroidppocr.bean.ModelType;
import com.equationl.ncnnandroidppocr.bean.OcrResult;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;

/** Actual native ncnn model/inference, not a mocked OCR parser. */
@RunWith(AndroidJUnit4.class)
public class ScreenshotNcnnOcrTest {
    @Test
    public void modelInitializesAndRecognizesImage() {
        Context ctx = InstrumentationRegistry.getInstrumentation().getTargetContext();
        OCR ocr = new OCR();
        assertTrue("Bundled models must initialize on Android",
                ocr.initModelFromAssert(ctx.getAssets(), ModelType.Mobile,
                        ImageSize.Size720, Device.CPU));
        Bitmap bitmap = Bitmap.createBitmap(1080, 480, Bitmap.Config.ARGB_8888);
        try {
            Canvas canvas = new Canvas(bitmap);
            canvas.drawColor(Color.WHITE);
            Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
            paint.setColor(Color.BLACK);
            paint.setTextSize(110f);
            paint.setFakeBoldText(true);
            canvas.drawText("ABC123", 90f, 245f, paint);
            OcrResult found = ocr.detectBitmap(bitmap, DrawModel.None);
            assertNotNull("Native inference should return OCR output", found);
            Log.i("AG_REAL_OCR", "ncnn lines=" + found.getTextLines().size()
                    + " content=" + found.getText()
                    + " inference_ms=" + found.getInferenceTime());
            assertFalse("Native model should recognize a large text line",
                    found.getTextLines().isEmpty());
        } finally {
            bitmap.recycle();
            ocr.release();
        }
    }
}
