module scid.demos.zmat;

version( demo ):
import scid.demos.common;
import std.math;

/** Test a medley of operations on complex-valued matrices. */
void zMatOpsTest() {
    alias Matrix!cdouble            zGeMat;
    alias SymmetricMatrix!cdouble   zSyMat;

    auto a = zGeMat( 3, [1.+4i,2+3i,3+2i,4+1i,5+0i,6-1i,7-2i,8-3i,9-4i] );
    auto b = zGeMat( 3, [1.+2i,2.+1i,3+0i,4-1i,5-2i,6-3i] );

    zGeMat c = b * a;
    enforceMatData( c, 2, 3, [ 18 + 19i, 33 + 22i, 45 - 8i, 60 - 23i, 72 -35i, 87 - 68i ] );


    c[] = c[0 .. 2][ 0 .. 2 ].t * ( (b[][0] - a[1..3][0]).t * eval(c[][0]) ) / (cast(cdouble) 10.);
    enforceMatData( c, 2, 2, [-146.60 + 192.80i, -422.00 -  28.60i, -281.60 + 235.40i, -575.00 - 151.60i] );

    c[] = c + zGeMat([[150-190i,280-230i], [430+28i,570+150i]]);
// Issue 84
    zSyMat s = c.t*c;

    enforceMatData( s, 2, 2, [ 83.760 +  0.000i,
                       -29.360 +  7.040i,
                        59.280 +  0.000i ]);


    enforce( abs(s[1][0] - (-29.360 - 7.040i)) <= 1e-3 );

    auto d = eval( s - zSyMat([80.+0i,-28,59]) );
    static assert( is( typeof(d) : zSyMat ) );

    enforceMatData( d, 2, 2, [ 3.76 + 0.0i, -1.36 + 7.04i, 0.28 + 0.0i ] );


    enforce( abs(d[1][0] - (-1.36 - 7.04i)) <= 1e-3 );


    auto e = eval( d + b[0..2][1..3]*(10.+0i) );
    static assert( is( typeof(e) : zGeMat ) );

    enforceMatData( e, 2, 2, [ 33.760 +  0.000i, 38.640 - 17.040i, 48.640 - 12.960i, 60.280 - 30.000i] );
}
