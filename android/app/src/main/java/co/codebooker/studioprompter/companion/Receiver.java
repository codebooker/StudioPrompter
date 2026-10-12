package co.codebooker.studioprompter.companion;
import android.content.Context;
import android.net.nsd.*;
import android.net.wifi.WifiManager;
import android.os.*;
import android.util.AtomicFile;
import org.bouncycastle.tls.TlsClientProtocol;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import javax.net.ssl.*;

public final class Receiver {
    public interface Listener {void hosts(List<NsdServiceInfo> hosts);void status(String text,boolean connected);void document(JSONObject doc);void playback(JSONObject state);}
    private final Context context;private final Listener listener;private final Handler ui=new Handler(Looper.getMainLooper());
    private final ExecutorService worker=Executors.newSingleThreadExecutor();private final NsdManager nsd;private final AtomicFile file;
    private final List<NsdServiceInfo> hosts=new ArrayList<>();private final ArrayDeque<NsdServiceInfo> resolveQueue=new ArrayDeque<>();private boolean resolving=false;
    private NsdManager.DiscoveryListener discovery;private WifiManager.MulticastLock multicast;private volatile Socket socket;private volatile long generation=0;
    private JSONObject saved;private boolean automatic=true,connecting=false,connected=false;private String revision=null;
    public Receiver(Context context,Listener listener){this.context=context;this.listener=listener;nsd=(NsdManager)context.getSystemService(Context.NSD_SERVICE);file=new AtomicFile(new File(context.getFilesDir(),"paired-producer.json"));try{saved=new JSONObject(new String(file.readFully(),StandardCharsets.UTF_8));}catch(Exception ignored){} }
    public boolean hasPairing(){return saved!=null&&!saved.optBoolean("removed");}
    public void browse(){
        automatic=true;if(discovery!=null)return;
        WifiManager wifi=(WifiManager)context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);if(wifi!=null){multicast=wifi.createMulticastLock("StudioPrompter discovery");multicast.setReferenceCounted(false);multicast.acquire();}
        discovery=new NsdManager.DiscoveryListener(){
            public void onDiscoveryStarted(String type){}
            public void onStartDiscoveryFailed(String type,int error){ui.post(()->status("Search unavailable. Check Wi-Fi, then reopen the companion.",false));}
            public void onDiscoveryStopped(String type){}
            public void onStopDiscoveryFailed(String type,int error){}
            public void onServiceFound(NsdServiceInfo info){ui.post(()->{if(discovery!=null&&info.getServiceType().contains("_studioprompt._tcp")){resolveQueue.add(info);resolveNext();}});}
            public void onServiceLost(NsdServiceInfo info){ui.post(()->{hosts.removeIf(h->h.getServiceName().equals(info.getServiceName()));listener.hosts(Collections.unmodifiableList(new ArrayList<>(hosts)));});}
        };
        try{nsd.discoverServices("_studioprompt._tcp.",NsdManager.PROTOCOL_DNS_SD,discovery);}catch(Exception e){status("Unable to discover producers on this network.",false);}
        if(saved!=null&&saved.optBoolean("removed"))status("This tablet was removed by the producer. Pair again to reconnect.",false);else status("Looking for StudioPrompter · use the same local network",false);
    }
    private void resolveNext(){if(resolving||resolveQueue.isEmpty())return;resolving=true;NsdServiceInfo info=resolveQueue.remove();nsd.resolveService(info,new NsdManager.ResolveListener(){
        public void onResolveFailed(NsdServiceInfo value,int error){ui.post(()->{resolving=false;resolveNext();});}
        public void onServiceResolved(NsdServiceInfo value){ui.post(()->{if(discovery==null){resolving=false;return;}hosts.removeIf(h->h.getServiceName().equals(value.getServiceName()));hosts.add(value);listener.hosts(Collections.unmodifiableList(new ArrayList<>(hosts)));resolving=false;resolveNext();if(automatic&&hasPairing()&&!connecting&&!connected&&value.getServiceName().startsWith(saved.optString("serviceName")))reconnect();});}
    });}
    private void status(String text,boolean online){connected=online;listener.status(text,online);}
    public void pair(NsdServiceInfo host,String code){String key=Protocol.normalize(code);if(key.length()!=12){status("Enter the 12-character code shown on the producer computer.",false);return;}open(host,key,null);}
    public void reconnect(){if(!hasPairing())return;for(NsdServiceInfo host:hosts)if(host.getServiceName().startsWith(saved.optString("serviceName"))){open(host,saved.optString("token"),saved);return;}status("Producer unavailable. Open StudioPrompter on the same network.",false);automatic=true;}
    private void open(NsdServiceInfo host,String key,JSONObject prior){
        disconnect(false);automatic=true;connecting=true;final long run=++generation;status("Connecting securely…",false);
        worker.execute(()->{
            Socket active=null;boolean authorized=false;String finalStatus="Connection lost · script held in place";
            try{
                active=new Socket();socket=active;active.setTcpNoDelay(true);active.setSoTimeout(15000);active.connect(new InetSocketAddress(host.getHost(),host.getPort()),10000);TlsClientProtocol transport=PskTransport.connect(active,key);
                if(run!=generation)return;
                DataInputStream in=new DataInputStream(transport.getInputStream());DataOutputStream out=new DataOutputStream(transport.getOutputStream());
                JSONObject request=prior==null?Protocol.message("pair",new JSONObject().put("version",2).put("name",Build.MANUFACTURER+" "+Build.MODEL).put("code",key)):
                    Protocol.message("resume",new JSONObject().put("version",2).put("deviceID",prior.getString("deviceID")).put("token",prior.getString("token")));
                Protocol.write(out,request);
                while(run==generation){JSONObject message=Protocol.read(in);if(run!=generation)break;
                    if(message.has("paired")){
                        if(authorized)throw new IOException("Duplicate authorization");JSONObject value=message.getJSONObject("paired").getJSONObject("_0");String token=value.getString("token"),hostID=value.getString("hostID"),deviceID=value.getString("deviceID");
                        UUID.fromString(hostID);UUID.fromString(deviceID);
                        if(value.optBoolean("removed")||!token.matches("[A-Fa-f0-9]{64}")||value.getString("name").length()>256||!value.getString("serviceName").equals("StudioPrompter-"+hostID.substring(0,8))||prior!=null&&(!prior.getString("hostID").equals(hostID)||!prior.getString("deviceID").equals(deviceID)||!prior.getString("token").equals(token)))throw new IOException("Invalid pairing");
                        persist(value);saved=value;authorized=true;ui.post(()->{if(run==generation)saved=value;});active.setSoTimeout(2500);
                    }else if(message.has("document")){
                        JSONObject d=message.getJSONObject("document").getJSONObject("_0");if(!authorized||!Protocol.validDocument(d))throw new IOException("Invalid document");revision=d.getString("revision");ui.post(()->{if(run==generation)listener.document(d);});
                    }else if(message.has("playback")){
                        JSONObject p=message.getJSONObject("playback").getJSONObject("_0");if(!authorized||!Protocol.validPlayback(p,revision))throw new IOException("Invalid playback");ui.post(()->{if(run==generation){connecting=false;status("Connected to "+host.getServiceName(),true);listener.playback(p);}});
                    }else if(message.has("removed")){
                        if(prior==null&&!authorized)throw new IOException("Invalid removal");JSONObject value=new JSONObject((prior==null?saved:prior).toString()).put("removed",true);persist(value);ui.post(()->{saved=value;automatic=false;});finalStatus="This tablet was removed by the producer. Pair again to reconnect.";break;
                    }else if(message.has("unavailable")){
                        finalStatus=message.getJSONObject("unavailable").optString("_0","Producer unavailable");if(finalStatus.length()>512)throw new IOException("Invalid status");break;
                    }else if(message.has("stopped")){finalStatus="The producer stopped tablet output. Your pairing is kept.";break;}
                    else throw new IOException("Unsupported message");
                }
            }catch(Exception e){if(!authorized)finalStatus=prior==null?"Could not pair. Check the current code and local network.":"Could not reach the producer. Check the local network and try Reconnect.";}
            finally{
                try{if(active!=null)active.close();}catch(IOException ignored){}String message=finalStatus;ui.post(()->{if(run==generation){socket=null;connecting=false;status(message,false);}});
            }
        });
    }
    private void persist(JSONObject value)throws IOException{FileOutputStream stream=null;try{stream=file.startWrite();stream.write(value.toString().getBytes(StandardCharsets.UTF_8));file.finishWrite(stream);}catch(Exception e){if(stream!=null)file.failWrite(stream);throw new IOException("Could not save pairing",e);}}
    public void disconnect(boolean deliberate){generation++;connecting=false;connected=false;if(deliberate)automatic=false;Socket old=socket;socket=null;try{if(old!=null)old.close();}catch(Exception ignored){}if(deliberate)status(hasPairing()?"Disconnected · pairing saved. Tap Reconnect when ready.":"Choose a producer to begin.",false);}
    public void forget(){disconnect(true);file.delete();saved=null;status("Pairing forgotten. Enter a new producer code.",false);}
    public void stop(){automatic=false;disconnect(false);if(discovery!=null){try{nsd.stopServiceDiscovery(discovery);}catch(Exception ignored){}discovery=null;}if(multicast!=null&&multicast.isHeld())multicast.release();hosts.clear();resolveQueue.clear();resolving=false;}
    public void close(){stop();worker.shutdownNow();}
}
