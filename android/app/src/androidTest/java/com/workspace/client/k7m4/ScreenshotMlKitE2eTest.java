package com.workspace.client.k7m4;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.util.Log;

import androidx.test.ext.junit.runners.AndroidJUnit4;

import com.google.android.gms.tasks.Tasks;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.Text;
import com.google.mlkit.vision.text.TextRecognition;
import com.google.mlkit.vision.text.TextRecognizer;
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;

import static org.junit.Assert.*;

/**
 * Image -> actual bundled Chinese ML Kit OCR, executed inside an Android
 * emulator. Unlike Dart parser tests, these calls exercise real recognition
 * of raster pixels. Names are fictional; no customer's private screenshots
 * are stored in the public repository.
 *
 * The original user screenshots remain private. Their page structures,
 * coordinates, font sizes, and price/title placements inform these fixtures,
 * but synthetic fixtures are NOT a substitute for pixel-identical originals.
 */
@RunWith(AndroidJUnit4.class)
public final class ScreenshotMlKitE2eTest {
    private static final int W = 692;
    private static final int H = 1536;

    private static final class Fixture {
        final Bitmap bitmap = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888);
        final Canvas canvas = new Canvas(bitmap);
        final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        Fixture(boolean dark) {
            canvas.drawColor(dark ? Color.rgb(22, 24, 26) : Color.WHITE);
            paint.setTypeface(Typeface.create("sans-serif", Typeface.NORMAL));
            paint.setColor(dark ? Color.WHITE : Color.BLACK);
        }
        Fixture label(String value, int x, int baseline, float size) {
            paint.setTextSize(size);
            canvas.drawText(value, x, baseline, paint);
            return this;
        }
        Fixture yen(String amount, int x, int baseline) {
            paint.setColor(Color.rgb(227, 152, 22));
            label(amount, x, baseline, 26);
            paint.setColor(Color.BLACK);
            return this;
        }
    }

    private List<Text.Line> recognize(String fixtureName, Bitmap image) throws Exception {
        final TextRecognizer engine = TextRecognition.getClient(
            new ChineseTextRecognizerOptions.Builder().build()
        );
        try {
            Text recognized = Tasks.await(
                engine.process(InputImage.fromBitmap(image, 0)),
                80, TimeUnit.SECONDS
            );
            final List<Text.Line> items = new ArrayList<>();
            for (Text.TextBlock block : recognized.getTextBlocks()) {
                for (Text.Line line : block.getLines()) {
                    items.add(line);
                    Log.i("AG_REAL_OCR", fixtureName + " | " + line.getText() +
                        " | " + line.getBoundingBox());
                }
            }
            assertFalse(fixtureName + ": real OCR returned no text", items.isEmpty());
            return items;
        } finally {
            engine.close();
            image.recycle();
        }
    }

    private static String joined(List<Text.Line> lines) {
        StringBuilder s = new StringBuilder();
        for (Text.Line line : lines) {
            s.append(line.getText()).append('\n');
        }
        return s.toString();
    }

    @Test
    public void miHuashiListRealPixels() throws Exception {
        Fixture f = new Fixture(false);
        f.label("进行中    已完成", 143, 125, 28);
        f.label("默认       截稿时间        接单时间", 60, 200, 20);
        int[] offsets = { 0, 455, 905 };
        String[] clients = { "测试买家甲", "测试买家乙", "测试买家丙" };
        for (int i=0;i<3;i++) {
            int y=offsets[i];
            f.label(clients[i], 115, 320+y, 26);
            f.label("【常驻】黑白摸鱼头3.0", 280, 420+y, 24);
            f.yen("¥94", 277, 462+y);
            f.label("2026-10-31", 308, 530+y, 23);
            f.label("60%", 340, 568+y, 20);
        }
        String text = joined(recognize("MI_LIST", f.bitmap));
        assertTrue("Should recognize at least some of the listing title: " + text,
            text.contains("黑白") || text.contains("摸鱼"));
        assertTrue("Should recognize amount ¥94: " + text, text.contains("94"));
    }

    @Test
    public void huajiaListRightCornerPrices() throws Exception {
        Fixture f = new Fixture(false);
        f.label("我卖出的", 285, 118, 32);
        int[] offsets = { 0, 360, 715, 1080 };
        int[] prices = { 30, 88, 30, 800 };
        String[] clients = { "客户甲", "客户乙", "客户丙", "客户丁" };
        for (int i=0;i<4;i++) {
            int y=offsets[i];
            f.label(clients[i], 90, 270+y, 24);
            f.label(i==1 ? "虚构摸鱼草盒" : "黑白草稿盒", 200, 346+y, 24);
            f.label("当前交付节点：终稿（100%）", 198, 376+y, 16);
            f.label("截稿时间：2026-10-08 16:48", 198, 405+y, 16);
            if (i<3) f.label("¥" + prices[i], 620, 488+y, 21);
        }
        String text = joined(recognize("HU_LIST", f.bitmap));
        assertTrue("Huajia list should preserve card title: "+text,
            text.contains("草稿盒") || text.contains("摸鱼"));
        // Diagnostic: first three amounts should all be visible to the engine.
        assertTrue("Tiny lower-right price 30 not detected: "+text, text.contains("30"));
        assertTrue("Tiny lower-right price 88 not detected: "+text, text.contains("88"));
    }

    @Test
    public void miHuashiDetailWithFileUploadDate() throws Exception {
        Fixture f = new Fixture(false);
        f.label("订单", 313, 120, 32);
        f.label("【这是】摸鱼盒子", 187, 207, 26);
        f.label("截稿时间 2026-07-13 21:05", 175, 279, 18);
        f.label("测试买家", 110, 380, 24);
        f.label("约稿完成！稿酬 ¥88", 36, 497, 27);
        f.label("稿件夹     进程动态      参考信息", 32, 613, 23);
        f.label("插画34.png", 192, 754, 22);
        f.label("2026-07-10 11:55", 192, 794, 17);
        String text = joined(recognize("MI_DETAIL", f.bitmap));
        assertTrue("Need recognizable detail title: "+text,
            text.contains("摸鱼") || text.contains("盒子"));
        assertTrue("Fee missing: "+text, text.contains("88"));
    }

    @Test
    public void huajiaDetailDarkHeaderAndFiles() throws Exception {
        Fixture f = new Fixture(true);
        f.label("订单已完成", 245, 133, 31);
        f.label("虚构用户", 103, 275, 24);
        f.label("真爱永恒 Lv1", 318, 275, 19);
        f.label("【24h】速食短打+赠捡手", 204, 360, 24);
        f.label("¥40", 198, 408, 22);
        f.label("截稿时间：2025-04-27 16:37", 195, 446, 19);
        f.label("稿件 6     订单动态    改价历史    参考信息", 25, 588, 22);
        f.label("2025-04-27", 40, 1025, 18);
        String text = joined(recognize("HU_DETAIL", f.bitmap));
        assertTrue("Huajia detail header lost: "+text,
            text.contains("订单") || text.contains("已完成"));
        assertTrue("Fee ¥40 must be present: "+text, text.contains("40"));
    }
}
