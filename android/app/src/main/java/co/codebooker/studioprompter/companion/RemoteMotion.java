package co.codebooker.studioprompter.companion;
import java.util.ArrayDeque;
public final class RemoteMotion {
    private static final class Sample { final double time, progress; Sample(double time,double progress){this.time=time;this.progress=progress;} }
    private final ArrayDeque<Sample> samples=new ArrayDeque<>();
    public void clear(){samples.clear();}
    public void add(double progress,double time,boolean snap){if(snap||(!samples.isEmpty()&&Math.abs(samples.getLast().progress-progress)>.035))samples.clear();samples.add(new Sample(time,progress));while(samples.size()>8)samples.removeFirst();}
    public double position(double now){if(samples.isEmpty())return 0;double target=now-.1;Sample a=samples.getFirst();if(target<=a.time)return a.progress;for(Sample b:samples){if(target<=b.time){double mix=Math.max(0,Math.min(1,(target-a.time)/Math.max(.001,b.time-a.time)));return a.progress+(b.progress-a.progress)*mix;}a=b;}return samples.getLast().progress;}
}
