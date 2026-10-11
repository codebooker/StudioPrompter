package co.codebooker.studioprompter.companion;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;
import java.io.*;
import java.net.Socket;
import org.json.*;
import org.bouncycastle.tls.TlsClientProtocol;

@RunWith(AndroidJUnit4.class)
public class NetworkTest {
 @Test public void pairsAndReconnectsUsingTheAndroidTlsImplementation()throws Exception{
  String argument=InstrumentationRegistry.getArguments().getString("studioPort");
  if(argument==null)throw new AssertionError("The desktop TLS fixture port is required");
  int port=Integer.parseInt(argument);JSONObject saved;
  try(Socket socket=new Socket("10.0.2.2",port)){
   socket.setSoTimeout(5000);TlsClientProtocol tls=PskTransport.connect(socket,"ABCDEFGHJKLM");
   Protocol.write(new DataOutputStream(tls.getOutputStream()),Protocol.message("pair",new JSONObject().put("version",2).put("name","Android emulator").put("code","ABCDEFGHJKLM")));
   saved=Protocol.read(new DataInputStream(tls.getInputStream())).getJSONObject("paired").getJSONObject("_0");assertEquals(64,saved.getString("token").length());
  }
  Thread.sleep(100);
  try(Socket socket=new Socket("10.0.2.2",port)){
   socket.setSoTimeout(5000);TlsClientProtocol tls=PskTransport.connect(socket,saved.getString("token"));
   Protocol.write(new DataOutputStream(tls.getOutputStream()),Protocol.message("resume",new JSONObject().put("version",2).put("deviceID",saved.getString("deviceID")).put("token",saved.getString("token"))));
   assertEquals(saved.getString("deviceID"),Protocol.read(new DataInputStream(tls.getInputStream())).getJSONObject("paired").getJSONObject("_0").getString("deviceID"));
  }
 }
}
