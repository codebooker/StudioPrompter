package co.codebooker.studioprompter.companion;
import android.content.Context;
import android.graphics.*;
import android.os.SystemClock;
import android.text.*;
import android.text.style.*;
import android.view.View;
import org.json.*;
import java.util.ArrayList;

public final class RemoteCanvas extends View {
    private JSONObject document,playback,settings;
    private final ArrayList<StaticLayout> layouts=new ArrayList<>();
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RemoteMotion motion=new RemoteMotion();
    public RemoteCanvas(Context context){super(context);setBackgroundColor(Color.rgb(14,15,18));}
    public void document(JSONObject value) throws Exception {
        document=value;settings=value.getJSONObject("script").getJSONObject("settings");playback=null;motion.clear();layouts.clear();
        JSONObject script=value.getJSONObject("script");SpannableString text=new SpannableString(script.getString("text"));
        JSONArray marks=script.optJSONArray("emphasis");if(marks!=null)for(int i=0;i<marks.length();i++){JSONObject m=marks.getJSONObject(i);int start=m.optInt("location",-1),len=m.optInt("length",0);if(start<0||len<=0||start>text.length()-len)continue;if(m.optBoolean("bold"))text.setSpan(new StyleSpan(Typeface.BOLD),start,start+len,0);if(m.optBoolean("underline"))text.setSpan(new UnderlineSpan(),start,start+len,0);}
        TextPaint font=new TextPaint(Paint.ANTI_ALIAS_FLAG);font.setColor(Color.rgb(245,245,245));font.setTextSize((float)settings.getDouble("fontSize"));font.setTypeface(Typeface.create(settings.optString("typeface").equals("georgia")?"serif":"sans-serif",Typeface.NORMAL));
        JSONArray lines=document.getJSONArray("lines");for(int i=0;i<lines.length();i++){JSONObject l=lines.getJSONObject(i);int start=l.getInt("location"),end=start+l.getInt("length");while(end>start&&(text.charAt(end-1)=='\n'||text.charAt(end-1)=='\r'))end--;layouts.add(StaticLayout.Builder.obtain(text,start,end,font,100000).setIncludePad(false).build());}
        invalidate();
    }
    public void playback(JSONObject value){playback=value;motion.add(value.optDouble("progress"),SystemClock.elapsedRealtime()/1000.0,!value.optBoolean("playing"));invalidate();}
    @Override protected void onDraw(Canvas canvas){super.onDraw(canvas);if(document==null||playback==null||playback.optBoolean("blackout")||getWidth()==0)return;
        float scale=getWidth()/1000f,height=getHeight()/scale,font=(float)settings.optDouble("fontSize"),guide=height*(float)settings.optDouble("guidePosition");
        float origin=guide-font*.2f-(float)motion.position(SystemClock.elapsedRealtime()/1000.0)*(float)Math.max(0,document.optDouble("textHeight")-font*1.2);
        RectF band=new RectF(0,guide-8,1000,guide+(float)(document.optDouble("lineHeight")*settings.optDouble("guideLines"))+4);RectF nominal=new RectF(band);JSONArray lines=document.optJSONArray("lines");
        for(int i=0;i<lines.length();i++){JSONObject l=lines.optJSONObject(i);float y=(float)l.optDouble("y")+origin,h=(float)l.optDouble("height");if(y<nominal.bottom&&y+h>nominal.top)band.union(0,y-2,1000,y+h+2);}
        canvas.save();canvas.scale(scale,scale);canvas.translate(settings.optBoolean("mirrorHorizontal")?1000:0,settings.optBoolean("mirrorVertical")?height:0);canvas.scale(settings.optBoolean("mirrorHorizontal")?-1:1,settings.optBoolean("mirrorVertical")?-1:1);
        if(settings.optBoolean("showGuide")){paint.setColor(Color.argb(12,255,130,79));canvas.drawRect(band,paint);paint.setColor(Color.rgb(255,130,79));Path arrow=new Path();arrow.moveTo(30,guide+10);arrow.lineTo(44,guide+23);arrow.lineTo(30,guide+36);arrow.close();canvas.drawPath(arrow,paint);}
        boolean focus=settings.optBoolean("focusMode");drawLines(canvas,lines,origin,height,focus?92:255);if(focus){canvas.save();canvas.clipRect(band);drawLines(canvas,lines,origin,height,255);canvas.restore();}
        String overlay=playback.optInt("countdown")>0?Integer.toString(playback.optInt("countdown")):playback.optString("notice","");if(!overlay.isEmpty()&&!overlay.equals("null")){paint.setColor(Color.WHITE);paint.setTextSize(playback.optInt("countdown")>0?140:24);paint.setTypeface(Typeface.DEFAULT_BOLD);canvas.drawText(overlay,(1000-paint.measureText(overlay))/2,playback.optInt("countdown")>0?height/2:height-40,paint);}
        canvas.restore();if(playback.optBoolean("playing"))postInvalidateOnAnimation();
    }
    private void drawLines(Canvas canvas,JSONArray lines,float origin,float height,int alpha){for(int i=0;i<lines.length()&&i<layouts.size();i++){JSONObject l=lines.optJSONObject(i);float y=(float)l.optDouble("y")+origin;if(y+l.optDouble("height")<0||y>height)continue;StaticLayout layout=layouts.get(i);layout.getPaint().setAlpha(alpha);canvas.save();canvas.translate((float)settings.optDouble("margin"),y);layout.draw(canvas);canvas.restore();}}
}
