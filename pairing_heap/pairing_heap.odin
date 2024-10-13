/* [[file:../nubs.org::*pairing heap][pairing heap:3]] */
package pairing_heap

Pairing_Heap :: struct($T: typeid) {
	left, right, parent: ^Pairing_Heap(T),
	elem: T,
	less: proc(a, b: T) -> bool,
}

init :: proc(ph: ^$P/Pairing_Heap($T), less: proc(a, b: T) -> bool) {
	ph.less = less
}

meld :: proc(p1, p2: ^$T/Pairing_Heap) -> ^T {
	link :: proc(a, b: ^$T/Pairing_Heap) -> ^T { // a is always less than b here
		if a != nil && b != nil && a.right == b {
			//   a              a
			//  / \            / \
			// al  b     ->   b   br
			//    / \        / \
			//   bl  br     bl al
			tmp := a.left
			a.left = b          ; a.left.parent = a
			a.right = b.right   ; if a.right != nil do a.right.parent = a
			b.right = tmp       ; if b.right != nil do b.right.parent = b
		} else if a != nil && b != nil && b.right == a {
			//   b              a
			//  / \            / \
			// bl  a     ->   b   ar
			//    / \        / \
			//   al  ar     bl al
			tmp := a.left
			a.left = b          ; a.left.parent = a
			b.right = tmp       ; if b.right != nil do b.right.parent = b
		} else if a.left != nil {
			//   a        b          a
			//  / \   +  / \    =   / \
			// al ar    bl br      b  ar
			//                    / \
			//                   bl  br
			//                        \
			//                         al
			prev := b
			for tmp := b; tmp != nil; tmp = tmp.right { prev = tmp }
			prev.right = a.left ; if prev.right != nil do prev.right.parent = prev
			a.left = b          ; if a.left != nil do a.left.parent = a
		} else {
			a.left = b          ; if a.left != nil do a.left.parent = a
		}
		return a
	}

	if p1 == nil {
		return p2
	} else if p2 == nil {
		return p1
	} else if p1.less(p1.elem, p2.elem) {
		return link(p1, p2)
	} else {
		return link(p2, p1)
	}
}

push :: proc(root: ^^$T/Pairing_Heap, node: ^$P/Pairing_Heap) {
	root^ = meld(root^, node)
}

pop :: proc(root: ^^$T/Pairing_Heap) -> ^T {
	//       x
	//      / \
	//     xl  xr   ->   xl
	//    / \           / \
	//   a   b         a   b...
	//                      \
	//                      xr
	if root == nil do return nil
	x := root^;     // keep the ptr around
	root^ = x.left
	xr := x.right
	tmp := x.left
	for ; tmp != nil && tmp.right != nil; tmp = tmp.right {}
	if tmp != nil {
		tmp.right = x.right; if tmp.right != nil do tmp.right.parent = tmp
	}
	
	_merge_pairs :: proc(r: ^$T/Pairing_Heap) -> ^T {
		if r == nil {
			return nil
		} else if r.right == nil {
			return r
		} else {
			rrr := r.right.right
			r.right.right = nil // cut this connection!
			return meld(meld(r, r.right), _merge_pairs(rrr))
		}
	}
	root^ = _merge_pairs(root^)
	return x
}

decrease_key :: proc(delta: f32, root: ^^$T/Pairing_Heap, p: ^$P/Pairing_Heap) {
	// if p is not root, cut the edge joining p to it's parent and link the two trees formed
	if p == nil do return
	p.elem.key -= delta
	if p != root^ {
		assert(p != nil && p.parent != nil)
		if p.parent.right == p {
			p.parent.right = nil
		} else {
			p.parent.left = nil
		}
		p.parent = nil
		
		root^ = meld(root^, p)
	}
}
/* pairing heap:3 ends here */
