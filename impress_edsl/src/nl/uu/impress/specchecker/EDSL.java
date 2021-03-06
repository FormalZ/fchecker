package nl.uu.impress.specchecker;

public class EDSL {
    public interface IntPred {
        boolean invoke(int i);
    }

    public interface Pred<A> {
        boolean invoke(A i);
    }

//    public interface IntPred2 {
//        boolean invoke(int i, int j);
//    }

    private static boolean g_forall(int aLength, int rBegin, int rEnd, IntPred pred) {
        for (int index = rBegin; index < rEnd; index++) {
            if (index < 0 || index >= aLength)
            	throw new ArrayIndexOutOfBoundsException("index=" + index + ", array length=" + aLength);
            if (!pred.invoke(index))
                return false;
        }
        return true;
    }

    private static boolean g_exists(int aLength, int rBegin, int rEnd, IntPred pred) {
        for (int index = rBegin; index < rEnd; index++) {
            if (index < 0 || index >= aLength)
            	throw new ArrayIndexOutOfBoundsException("index=" + index + ", array length=" + aLength);
            if (pred.invoke(index))
                return true;
        }
        return false;
    }

    public static <A> boolean with(A a, Pred<A> pred) {
      return pred.invoke(a);
    }

    public static boolean imp(boolean p, boolean q) {
    	return !p || q;
    }
    public static boolean forall(Object[] array, IntPred pred) {
        return g_forall(array.length, 0, array.length, pred);
    }

    public static boolean forall(int[] array, IntPred pred) {
        return g_forall(array.length, 0, array.length, pred);
    }

    public static boolean forall(double[] array, IntPred pred) {
        return g_forall(array.length, 0, array.length, pred);
    }

    //public static boolean forall(int[][] array, IntPred2 pred) {
    //    return g_forall(array.length, 0, array.length, pred);
    //}

    public static boolean forallr(Object[] array, int rBegin, int rEnd, IntPred pred) {
        return g_forall(array.length, rBegin, rEnd, pred);
    }

    public static boolean forallr(int[] array, int rBegin, int rEnd, IntPred pred) {
        return g_forall(array.length, rBegin, rEnd, pred);
    }

    public static boolean forallr(double[] array, int rBegin, int rEnd, IntPred pred) {
        return g_forall(array.length, rBegin, rEnd, pred);
    }

    public static boolean exists(Object[] array, IntPred pred) {
        return g_exists(array.length, 0, array.length, pred);
    }

    public static boolean exists(int[] array, IntPred pred) {
        return g_exists(array.length, 0, array.length, pred);
    }

    public static boolean exists(double[] array, IntPred pred) {
        return g_exists(array.length, 0, array.length, pred);
    }

    public static boolean existsr(Object[] array, int rBegin, int rEnd, IntPred pred) {
        return g_exists(array.length, rBegin, rEnd, pred);
    }

    public static boolean existsr(int[] array, int rBegin, int rEnd, IntPred pred) {
        return g_exists(array.length, rBegin, rEnd, pred);
    }

    public static boolean existsr(double[] array, int rBegin, int rEnd, IntPred pred) {
        return g_exists(array.length, rBegin, rEnd, pred);
    }

    public static class PreConditionError extends AssertionError { }
    public static class PostConditionError extends AssertionError { }

    public static void pre() {}

    public static void pre(boolean pre) {
        if(!pre) throw new PreConditionError() ;
    }

    public static void post() {}

    public static void post(boolean post) {
        if (!post) throw new PostConditionError() ;
    }
}