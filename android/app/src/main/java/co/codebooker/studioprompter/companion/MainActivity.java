package co.codebooker.studioprompter.companion;
import android.app.Activity;
import android.graphics.Color;
import android.net.nsd.NsdServiceInfo;
import android.os.*;
import android.view.*;
import android.widget.*;
import org.json.JSONObject;
import java.util.*;

public final class MainActivity extends Activity implements Receiver.Listener {
    private Receiver receiver;private RemoteCanvas canvas;private LinearLayout controls;private TextView status;
    private Spinner producers;private EditText code;private Button reconnect,disconnect;private List<NsdServiceInfo> hosts=List.of();
    private final Handler handler=new Handler(Looper.getMainLooper());private boolean connected=false;
    private final Runnable hide=()->{if(connected)controls.setVisibility(View.GONE);};
    private int dp(int n){return Math.round(n*getResources().getDisplayMetrics().density);}
    @Override public void onCreate(Bundle saved){super.onCreate(saved);
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,WindowManager.LayoutParams.FLAG_FULLSCREEN);
        FrameLayout root=new FrameLayout(this);canvas=new RemoteCanvas(this);root.addView(canvas,new FrameLayout.LayoutParams(-1,-1));
        controls=new LinearLayout(this);controls.setOrientation(LinearLayout.VERTICAL);controls.setPadding(dp(20),dp(16),dp(20),dp(16));controls.setBackgroundColor(Color.argb(245,24,26,30));
        FrameLayout.LayoutParams panel=new FrameLayout.LayoutParams(Math.min(getResources().getDisplayMetrics().widthPixels-dp(32),dp(560)),-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);panel.topMargin=dp(24);root.addView(controls,panel);
        TextView title=new TextView(this);title.setText("StudioPrompter Companion");title.setTextColor(Color.WHITE);title.setTextSize(24);controls.addView(title);
        status=new TextView(this);status.setTextSize(16);status.setTextColor(Color.rgb(175,184,197));status.setPadding(0,dp(12),0,dp(12));controls.addView(status);
        TextView network=new TextView(this);network.setText("Connect your tablet and producer computer to the same local network.");network.setTextColor(Color.LTGRAY);controls.addView(network);
        producers=new Spinner(this);controls.addView(producers,new LinearLayout.LayoutParams(-1,dp(52)));
        code=new EditText(this);code.setSingleLine();code.setHint("12-character pairing code");code.setTextColor(Color.WHITE);code.setHintTextColor(Color.GRAY);code.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS);controls.addView(code);
        LinearLayout buttons=new LinearLayout(this);buttons.setOrientation(LinearLayout.HORIZONTAL);controls.addView(buttons);
        button(buttons,"Pair",()->{if(!hosts.isEmpty())receiver.pair(hosts.get(producers.getSelectedItemPosition()),code.getText().toString());else status("No producer found. Open tablet output on your computer.",false);});
        reconnect=button(buttons,"Reconnect",()->receiver.reconnect());disconnect=button(buttons,"Disconnect",()->receiver.disconnect(true));
        LinearLayout second=new LinearLayout(this);controls.addView(second);button(second,"Hide",()->{if(connected)controls.setVisibility(View.GONE);});button(second,"Forget producer",()->receiver.forget());
        canvas.setOnClickListener(v->reveal());setContentView(root);receiver=new Receiver(this,this);
    }
    private Button button(LinearLayout row,String label,Runnable action){Button b=new Button(this);b.setText(label);row.addView(b,new LinearLayout.LayoutParams(0,dp(52),1));b.setOnClickListener(v->{reveal();action.run();});return b;}
    private void reveal(){controls.setVisibility(View.VISIBLE);handler.removeCallbacks(hide);if(connected)handler.postDelayed(hide,5000);}
    @Override public void hosts(List<NsdServiceInfo> value){hosts=value;ArrayAdapter<String> adapter=new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,value.stream().map(NsdServiceInfo::getServiceName).toArray(String[]::new));producers.setAdapter(adapter);}
    @Override public void status(String message,boolean online){boolean changed=connected!=online;connected=online;status.setText(message);code.setVisibility(online?View.GONE:View.VISIBLE);producers.setVisibility(online?View.GONE:View.VISIBLE);reconnect.setEnabled(receiver.hasPairing()&&!online);disconnect.setEnabled(online);if(online)getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);if(changed||!online)reveal();}
    @Override public void document(JSONObject doc){try{canvas.document(doc);}catch(Exception e){receiver.disconnect(true);status("Could not draw this document. Reconnect or update the companion.",false);}}
    @Override public void playback(JSONObject value){canvas.playback(value);}
    @Override protected void onStart(){super.onStart();if(receiver!=null)receiver.browse();}
    @Override protected void onStop(){handler.removeCallbacks(hide);if(receiver!=null)receiver.stop();connected=false;controls.setVisibility(View.VISIBLE);getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);super.onStop();}
    @Override protected void onDestroy(){if(receiver!=null)receiver.close();super.onDestroy();}
}
