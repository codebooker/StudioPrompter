package co.codebooker.studioprompter.companion;
import org.junit.Test;import static org.junit.Assert.*;import java.io.*;import org.json.*;
public class ProtocolTest {
 @Test public void unicodeRoundTrip()throws Exception{ByteArrayOutputStream bytes=new ByteArrayOutputStream();Protocol.write(new DataOutputStream(bytes),new JSONObject().put("script","🎙️ café 中文"));assertEquals("🎙️ café 中文",Protocol.read(new DataInputStream(new ByteArrayInputStream(bytes.toByteArray()))).getString("script"));}
 @Test public void rejectsOversizedFrame()throws Exception{byte[] bytes={(byte)0x7f,(byte)0xff,(byte)0xff,(byte)0xff};try{Protocol.read(new DataInputStream(new ByteArrayInputStream(bytes)));fail("Accepted oversized frame");}catch(IOException expected){}}
 @Test public void keyDerivationMatchesDesktop(){assertEquals("StudioPrompter-v2-"+hex(Protocol.hash("identity:ABCDEFGH2345")),Protocol.identity("abcd-efgh 2345"));}
 private String hex(byte[] value){StringBuilder result=new StringBuilder();for(byte b:value)result.append(String.format("%02x",b&255));return result.toString();}
 @Test public void motionInterpolatesAndFreezes(){RemoteMotion motion=new RemoteMotion();motion.add(.1,1,true);motion.add(.11,1.1,false);assertEquals(.105,motion.position(1.15),.00001);assertEquals(.11,motion.position(10),.00001);motion.add(.02,11,true);assertEquals(.02,motion.position(11),.00001);}
}
