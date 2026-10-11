package co.codebooker.studioprompter.companion;
import java.net.Socket;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import javax.net.ssl.KeyManager;
import javax.net.ssl.SSLEngine;

/** Conscrypt's documented duck-typed PSK interface, matching the Mac's v2 transport. */
public final class PskManager implements KeyManager {
    private final String identity; private final SecretKey key;
    public PskManager(String secret) { identity=Protocol.identity(secret);key=new SecretKeySpec(Protocol.hash(Protocol.normalize(secret)),"RAW"); }
    public String chooseServerKeyIdentityHint(Socket socket){return null;}
    public String chooseServerKeyIdentityHint(SSLEngine engine){return null;}
    public String chooseClientKeyIdentity(String hint,Socket socket){return identity;}
    public String chooseClientKeyIdentity(String hint,SSLEngine engine){return identity;}
    public SecretKey getKey(String hint,String value,Socket socket){return identity.equals(value)?key:null;}
    public SecretKey getKey(String hint,String value,SSLEngine engine){return identity.equals(value)?key:null;}
}
