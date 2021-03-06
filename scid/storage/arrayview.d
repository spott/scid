/** Implementation of the BasicArrayViewStorage vector storage, which is the view type associated with
    BasicArrayStorage, the default storage type for vectors.

    Authors:    Cristian Cobzarenco
    Copyright:  Copyright (c) 2011, Cristian Cobzarenco. All rights reserved.
    License:    Boost License 1.0
*/
module scid.storage.arrayview;

import scid.vector;

import scid.ops.eval, scid.ops.common;
import scid.storage.array, scid.storage.cowarray;
import scid.common.meta;
import scid.common.storagetraits;
import std.traits, std.range, std.algorithm;
import scid.internal.assertmessages;
import scid.blas;

alias scid.common.traits.ArrayTypeOf ArrayTypeOf;

/** Enumeration that specifies if the elements in an array view ar contiguous or not. */
enum ArrayViewType {
	Interval,
	Strided
}

/** Template that aliases to a contiguous (ArrayViewType.Interval) BasicArrayViewStorage. If it's given a floating
    point type it defaults to using CowArrayRef as container. If passed a container type is uses that.
*/
template ArrayViewStorage( ElementOrArray, VectorType vectorType = VectorType.Column )
		if( isScalar!(BaseElementType!ElementOrArray) ) {

	static if( isScalar!ElementOrArray ) {
		// if the given type is a floating point no. use CowArrayRef as container
		alias BasicArrayViewStorage!(
			CowArrayRef!ElementOrArray,
			ArrayViewType.Interval,
			vectorType
		) ArrayViewStorage;
	} else {
		// if the given type is a container use that as container
		alias BasicArrayViewStorage!(
			ElementOrArray,
			ArrayViewType.Interval,
			vectorType
		) ArrayViewStorage;
	}
}

/** Template that aliases to a strided (ArrayViewType.Strided) BasicArrayViewStorage. If it's given a floating
    point type it defaults to using CowArrayRef as container. If passed a container type is uses that.
*/
template StridedArrayViewStorage( ElementOrArray, VectorType vectorType = VectorType.Column )
		if( isScalar!(BaseElementType!ElementOrArray) ) {

	static if( isScalar!ElementOrArray ) {
		alias BasicArrayViewStorage!(
			CowArrayRef!ElementOrArray,
			ArrayViewType.Strided,
			vectorType
		) StridedArrayViewStorage;
	} else {
		alias BasicArrayViewStorage!(
			ElementOrArray,
			ArrayViewType.Strided,
			vectorType
		) StridedArrayViewStorage;
	}
}

/** This is the storage type used by ArrayStorage as view. It is the storage type for VectorView and StridedVectorView.
    Like all storage types it wraps a custom container reference type which is by default a ref-counted CowArray. This
    means that by default views are not invalidated if the original ArrayStorage goes out of scope, but the behaviour
    is of course governed by the container type.
*/
struct BasicArrayViewStorage( ContainerRef_, ArrayViewType strided_, VectorType vectorType_ ) {
	/** The wrapped container reference type. */
	alias ContainerRef_ ContainerRef;

	/** The type of the vector elements. */
	alias BaseElementType!ContainerRef ElementType;

	/** The orientation of the vector (row/column). */
	alias vectorType_ vectorType;

	/** The result of evaluating a transposition operation on this. */
	alias BasicArrayStorage!( ArrayTypeOf!ContainerRef, transposeVectorType!vectorType ) Transposed;

	/** The type returned by view(). */
	alias typeof( this ) View;

	/** The type returned by view() when passed a stride. */
	alias BasicArrayViewStorage!( ContainerRef, ArrayViewType.Strided, vectorType ) StridedView;

	/** Whether this view is strided (as opposed to contiguous). */
	enum isStrided = (strided_ == ArrayViewType.Strided );

	static if( isStrided ) {
		/** Construct a view from a container reference, a start index, length and a stride. */
		this()( ref ContainerRef containerRef, size_t iFirstIndex, size_t iLength, size_t iStride )
		in {
			assert( iStride != 0, "Zero stride in view construction" );
		} body {
			containerRef_ = containerRef;
			setParams_( iFirstIndex, iLength, iStride );
		}
	} else {
		/** Construct a view from a container reference, a start index and length. */
		this()( ref ContainerRef containerRef, size_t iFirstIndex, size_t iLength ) {
			containerRef_ = containerRef;
			setParams_( iFirstIndex, iLength );
		}
	}

	/** Allow construction of containers. This allows the creation of vector views without creating vectors. */
	this( A ... )( A args ) if( A.length > 0 && !is( A[ 0 ] == ContainerRef ) ) {
		containerRef_ = ContainerRef( args );
		static if( isStrided )
			setParams_( 0, containerRef_.length, 1 );
		else
			setParams_( 0, containerRef_.length );
	}

	/** Forces reference sharing with another Array. This will cause two storages to refer to the same array.
	    This is usually a bad idea - it is used internally for proxy objects. */
	void forceRefSharing( ref typeof(this) rhs ){
		this = rhs;
	}

	/** Assignment has reference semantics. */
	ref typeof( this ) opAssign( typeof( this ) rhs ) {
		firstIndex_ = rhs.firstIndex;
		length_     = rhs.length_;
		swap( rhs.containerRef_, containerRef_ );
		static if( isStrided )
			stride_ = rhs.stride_;
		return this;
	}

	/** Element access forwarded to the container. Part of the VectorStorage concept. */
	ElementType index( size_t i ) const
	in {
		checkBounds_( i );
	} body {
		return containerRef_.cdata[ map_( i ) ];
	}

	/** This method provides both simple opIndexAssign and opIndexOpAssign-like functionality.
	    If the operator template parameter is left empty then it performs a simple assignment.
	    Forwarded to the container.
	*/
	void indexAssign( string op="" )( ElementType rhs, size_t i )
	in {
		checkBounds_( i );
	} body {
		mixin("containerRef_.data[ map_( i ) ] " ~ op ~ "= rhs;");
	}

	/** Returns a another contiguous view of the array. Part of the VectorStorage concept. */
	View view( size_t start, size_t end )
	in {
		checkSliceIndices_( start, end );
	} body {
		static if( isStrided )
			return typeof( return )( containerRef_, map_(start), end-start, stride_ );
		else
			return typeof( return )( containerRef_, map_(start), end-start );
	}

	/** Returns another strided view of the array. Part of the VectorStorage concept. */
	StridedView view( size_t start, size_t end, size_t newStride )
	in {
		assert( newStride != 0, "Zero stride in view-of-view construction." );
		checkSliceIndices_( start, end );
	} body {
		size_t len = (end - start);
		len = len / newStride + ( (len % newStride) != 0 );
		static if( isStrided ) {
			newStride *= stride_;
			return typeof( return )( containerRef_, map_(start), len, newStride );
		} else {
			return typeof( return )( containerRef_, map_(start), len, newStride );
		}
	}

	/** Returns a slice of the array. Part of the VectorStorage concept. */
	alias view slice;


	/** Check if the length is the same as the one given and zero out all the elements. Part of the VectorStorage concept. */
	void resize( size_t rlength ) {
		resize( rlength, null );
		blas.scal( length_, Zero!ElementType, data, stride );
	}

	/** Check if the length is the same as the one given. Part of the VectorStorage concept. */
	void resize( size_t rlength, void* ) {
		assert( length == rlength, "Length mismatch in vector operation." );
	}

	/** Copy specialization. */
	void copy( Transpose tr, S )( auto ref S rhs ) if( isStridedVectorStorage!(S, ElementType) ) {
		stridedCopy!tr( rhs, this );
	}

	/** Use the common scale(), scaledAddition() and dot() methods for strided storages. */
	mixin StridedScalingAdditionDot;

	/** Forward range methods to the wrapped container. */
	void popFront()
	in {
		checkNotEmpty_!"popFront"();
	} body {

		static if( isStrided ) {
			firstIndex_ += stride_;
		} else
			++ firstIndex_;
		-- length_;
	}

	/// ditto
	void popBack()
	in {
		checkNotEmpty_!"popBack"();
	} body {
		-- length_;
	}

	@property {
		/** Get a const pointer to the memory used by this storage. */
		ElementType* data() {
			return containerRef_.data + firstIndex_;
		}

		/** Get a mutable pointer to the memory used by this storage. */
		const(ElementType)* cdata() const {
			if( isInitd_() )
				return containerRef_.cdata + firstIndex_;
			else
				return null;
		}

		/** The index in the array at which this view starts. */
		size_t firstIndex() const {
			return firstIndex_;
		}

		/** Forward range methods to the wrapped container, checking that the reference is initialized. */
		size_t length() const {
			return length_;
		}

		/// ditto
		bool empty() const {
			return length_ == 0;
		}

		/// ditto
		void front( ElementType newValue )
		in {
			checkNotEmpty_!"front setter"();
		} body {
			indexAssign( newValue, 0 );
		}

		/// ditto
		void back( ElementType newValue  )
		in {
			checkNotEmpty_!"back setter"();
		} body {
			indexAssign( newValue, length - 1 );
		}

		/// ditto
		ElementType front() const
		in {
			checkNotEmpty_!"front"();
		} body {
			return this.index( 0 );
		}

		/// ditto
		ElementType back() const
		in {
			checkNotEmpty_!"back"();
		} body {
			return index( length_ - 1 );
		}

		/** The stride of the view i.e. the index difference between two consecutive elements. */
		static if( isStrided ) {
			size_t stride() const { return stride_; }
		} else {
			enum stride = 1;
		}
	}

	/** Promotions for this type are inherited from ArrayStorage */
	template Promote( Other ) {
		alias Promotion!( BasicArrayStorage!(ArrayTypeOf!ContainerRef, vectorType), Other ) Promote;
	}

private:
	mixin ArrayChecks;

	static if( isStrided ) {
		void setParams_( size_t f, size_t l, size_t s ) {
			firstIndex_ = f;
			length_     = l;
			stride_ = s;
		}

		size_t map_( size_t i ) const {
			return i * stride_ + firstIndex_;
		}

		size_t stride_;
	} else {
		void setParams_( size_t f, size_t l ) {
			firstIndex_ = f;
			length_     = l;
		}

		size_t map_( size_t i ) const {
			return i + firstIndex_;
		}
	}

	bool isInitd_() const {
		return containerRef_.RefCounted.isInitialized();
	}

	size_t firstIndex_, length_;
	ContainerRef containerRef_;
}

unittest {
	// TODO: Write tests for ArrayViewStorage.
}
