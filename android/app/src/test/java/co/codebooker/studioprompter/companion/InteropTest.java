package co.codebooker.studioprompter.companion;
import org.junit.Test;import static org.junit.Assert.*;import java.io.*;import java.net.*;import org.json.*;import org.bouncycastle.tls.TlsClientProtocol;
public class InteropTest {
 @Test public void pairsResumesAndReceivesOfflineRemovalOverRealTls()throws Exception{
  String fixture=System.getProperty("studio.fixture");
  ProcessBuilder command=fixture==null?new ProcessBuilder("node",new File(System.getProperty("studio.repo"),"desktop/test/android-fixture.cjs").getAbsolutePath()):new ProcessBuilder(fixture);
  Process server=command.redirectError(ProcessBuilder.Redirect.INHERIT).start();
  try{
   JSONObject status=new JSONObject(new BufferedReader(new InputStreamReader(server.getInputStream())).readLine());int port=status.getInt("port");
   JSONObject saved;
   try(Socket socket=new Socket("127.0.0.1",port)){
    socket.setSoTimeout(5000);TlsClientProtocol tls=PskTransport.connect(socket,"ABCDEFGHJKLM");
    Protocol.write(new DataOutputStream(tls.getOutputStream()),Protocol.message("pair",new JSONObject().put("version",2).put("name","Android interop test").put("code","ABCDEFGHJKLM")));
    saved=Protocol.read(new DataInputStream(tls.getInputStream())).getJSONObject("paired").getJSONObject("_0");assertEquals(64,saved.getString("token").length());
   }
   Thread.sleep(100);
   try(Socket socket=new Socket("127.0.0.1",port)){
    socket.setSoTimeout(5000);TlsClientProtocol tls=PskTransport.connect(socket,saved.getString("token"));
    Protocol.write(new DataOutputStream(tls.getOutputStream()),Protocol.message("resume",new JSONObject().put("version",2).put("deviceID",saved.getString("deviceID")).put("token",saved.getString("token"))));
    assertEquals(saved.getString("deviceID"),Protocol.read(new DataInputStream(tls.getInputStream())).getJSONObject("paired").getJSONObject("_0").getString("deviceID"));
   }
   server.getOutputStream().write("REMOVE\n".getBytes());server.getOutputStream().flush();Thread.sleep(100);
   try(Socket socket=new Socket("127.0.0.1",port)){
    socket.setSoTimeout(5000);TlsClientProtocol tls=PskTransport.connect(socket,saved.getString("token"));
    Protocol.write(new DataOutputStream(tls.getOutputStream()),Protocol.message("resume",new JSONObject().put("version",2).put("deviceID",saved.getString("deviceID")).put("token",saved.getString("token"))));
    assertTrue(Protocol.read(new DataInputStream(tls.getInputStream())).has("removed"));
   }
  }finally{server.destroy();server.waitFor();}
 }
}
