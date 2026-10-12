package co.codebooker.studioprompter.companion;
import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import android.graphics.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;
import org.json.*;

@RunWith(AndroidJUnit4.class)
public class CanvasTest {
 @Test public void launchesAndDrawsReceivedScriptWithMirroringAndBlackout()throws Exception{
  try(ActivityScenario<MainActivity> scenario=ActivityScenario.launch(MainActivity.class)){
   scenario.onActivity(activity->{try{
    RemoteCanvas view=new RemoteCanvas(activity);view.layout(0,0,1000,600);
    String revision="01234567-89ab-cdef-0123-456789abcdef";
    JSONObject settings=new JSONObject().put("fontSize",54).put("margin",100).put("guidePosition",.3).put("guideLines",1).put("focusMode",false).put("showGuide",true).put("mirrorHorizontal",false).put("mirrorVertical",false).put("typeface","system");
    JSONObject document=new JSONObject().put("revision",revision).put("script",new JSONObject().put("text","A small thing can change everything.").put("settings",settings).put("emphasis",new JSONArray().put(new JSONObject().put("location",2).put("length",5).put("bold",true).put("underline",true))))
      .put("textHeight",80).put("lineHeight",80).put("lines",new JSONArray().put(new JSONObject().put("location",0).put("length",36).put("y",0).put("height",70)));
    assertTrue(Protocol.validDocument(document));view.document(document);
    JSONObject playback=new JSONObject().put("revision",revision).put("progress",0).put("playing",false).put("blackout",false).put("countdown",0);view.playback(playback);
    Bitmap normal=Bitmap.createBitmap(1000,600,Bitmap.Config.ARGB_8888);view.draw(new Canvas(normal));
    int bright=0;for(int y=140;y<270;y++)for(int x=80;x<960;x++)if(Color.red(normal.getPixel(x,y))>200)bright++;assertTrue("Script must be visible",bright>100);
    settings.put("mirrorHorizontal",true);view.document(document);view.playback(playback);Bitmap mirrored=Bitmap.createBitmap(1000,600,Bitmap.Config.ARGB_8888);view.draw(new Canvas(mirrored));
    int difference=0;for(int y=0;y<600;y++)for(int x=0;x<1000;x++)if(normal.getPixel(x,y)!=mirrored.getPixel(999-x,y))difference++;
    assertTrue("Mirror should preserve the same drawing",difference<3000);
    playback.put("blackout",true);view.playback(playback);Bitmap black=Bitmap.createBitmap(1000,600,Bitmap.Config.ARGB_8888);view.draw(new Canvas(black));assertEquals(Color.rgb(14,15,18),black.getPixel(200,200));
   }catch(Exception e){throw new AssertionError(e);}});
  }
 }
}
