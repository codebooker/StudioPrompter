package co.codebooker.studioprompter.companion;
import org.bouncycastle.tls.*;
import org.bouncycastle.tls.crypto.impl.bc.BcTlsCrypto;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;

/** Pure Java TLS-PSK: identical AES-GCM authentication to the Mac and iPad. */
public final class PskTransport {
    public static TlsClientProtocol connect(Socket socket,String key)throws java.io.IOException {
        TlsClientProtocol protocol=new TlsClientProtocol(socket.getInputStream(),socket.getOutputStream());
        BasicTlsPSKIdentity identity=new BasicTlsPSKIdentity(Protocol.identity(key).getBytes(StandardCharsets.UTF_8),Protocol.hash(Protocol.normalize(key)));
        protocol.connect(new PSKTlsClient(new BcTlsCrypto(new SecureRandom()),identity){
            @Override protected int[] getSupportedCipherSuites(){return new int[]{CipherSuite.TLS_PSK_WITH_AES_128_GCM_SHA256};}
            @Override protected ProtocolVersion[] getSupportedVersions(){return new ProtocolVersion[]{ProtocolVersion.TLSv12};}
        });
        return protocol;
    }
}
